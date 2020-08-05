let s:context_buffer_name = '<context.vim>'

function! context#popup#update_context() abort
    let [lines, base_line] = context#popup#get_context()
    call context#util#echof('> context#popup#update_context', len(lines))

    let w:context.lines  = lines
    let w:context.indent = g:context.Border_indent(base_line)

    call context#util#show_cursor()
    call s:show()
endfunction

" returns [lines, base_line_nr]
function! context#popup#get_context() abort
    call context#util#echof('context#popup#get_context')
    " NOTE: there's a problem if some of the hidden lines
    " (behind the popup) are wrapped. then our calculations are off
    " TODO: fix that?

    " a skipped line has the same context as the next unskipped one below
    let skipped       =  0
    let line_number   = w:context.cursor_line - 1 " first iteration starts with cursor_line
    let top_line      = w:context.top_line
    let border_height = g:context.show_border

    while 1
        let line_number += 1

        let indent = g:context.Indent(line_number) " -1 for invalid lines
        if indent < 0
            call context#util#echof('negative indent', line_number)
            return [[], 0]
        endif

        let text = getline(line_number) " empty for invalid lines
        if context#line#should_skip(text)
            let skipped += 1
            call context#util#echof('skip', line_number)
            continue
        endif

        let base_line = context#line#make(line_number, indent, text)
        let [context, line_count] = context#context#get(base_line)
        call context#util#echof('context#get', line_number, line_count)

        if line_count == 0
            return [[], 0]
        endif

        if w:context.fix_strategy == 'scroll'
            call context#util#echof('scroll: done')
            break
        endif

        " call context#util#echof('fit?', top_line, line_count, border_height, line_number)
        if top_line + line_count + border_height <= line_number
            " this context fits, use it
            break
        endif

        " try again on next line if this context doesn't fit
        let skipped = 0
    endwhile

    let [lines, line_number] = context#util#filter(context, line_number, 1)

    return [lines, line_number]
endfunction

function! context#popup#layout() abort
    call context#util#echof('> context#popup#layout')

    for winid in keys(g:context.popups)
        let popup = g:context.popups[winid]
        let winbuf = winbufnr(winid)
        let popupbuf = winbufnr(popup)

        if winbuf == -1 || popupbuf == -1
            if popupbuf != -1
                call s:close(popup)
            endif
            call remove(g:context.popups, winid)
            continue
        endif

        call context#util#update_window_state(winid)

        " NOTE: the context might be wrong as the top line might have
        " changed, but we can't really fix that (without temporarily
        " moving the cursor which we'd like to avoid)
        " TODO: fix that?
        call context#popup#redraw(winid)
    endfor
endfunction

function! context#popup#redraw(winid) abort
    let popup = get(g:context.popups, a:winid)
    if popup == 0
        return
    endif

    let c = getwinvar(a:winid, 'context', {})
    if c == {}
        return
    endif

    let lines = copy(c.lines)
    if len(lines) == 0
        return
    endif

    if g:context.show_border
        call add(lines, s:get_border_line(a:winid, 1))
    endif

    call context#util#echof('  > context#popup#redraw', len(lines))

    let display_lines = []
    let hls = [] " list of lists, one per context line
    for line in lines
        let [text, highlights] = context#line#display(line)
        call context#util#echof('highlights', text, highlights)
        call add(display_lines, text)
        call add(hls, highlights)
    endfor

    if g:context.presenter == 'nvim-float'
        call context#popup#nvim#redraw(a:winid, popup, display_lines)
    elseif g:context.presenter == 'vim-popup'
        call context#popup#vim#redraw(a:winid, popup, display_lines)
    endif

    let args = {'window': popup}
    for h in range(0, len(hls)-1)
        for hl in hls[h]
            call matchaddpos(hl[0], [[h+1, hl[1], hl[2]]], 10, -1, args)
        endfor
    endfor
endfunction

" close all popups
function! context#popup#clear() abort
    for key in keys(g:context.popups)
        call s:close(g:context.popups[key])
    endfor
    let g:context.popups = {}
endfunction

" close current popup
function! context#popup#close() abort
    let winid = win_getid()
    let popup = get(g:context.popups, winid)
    if popup == 0
        return
    endif

    call s:close(popup)
    call remove(g:context.popups, winid)
endfunction

" popup related
function! s:show() abort
    let winid = win_getid()
    let popup = get(g:context.popups, winid)
    let popupbuf = winbufnr(popup)

    if popup > 0 && popupbuf == -1
        let popup = 0
        call remove(g:context.popups, winid)
    endif

    if len(w:context.lines) == 0
        call context#util#echof('  no lines')

        if popup > 0
            call s:close(popup)
            call remove(g:context.popups, winid)
        endif
        return
    endif

    if popup == 0
        let popup = s:open()
        let g:context.popups[winid] = popup
    endif

    call context#popup#redraw(winid)

    if g:context.presenter == 'nvim-float'
        call context#popup#nvim#redraw_screen()
    endif
endfunction

" TODO: consider fold column too

function! s:open() abort
    call context#util#echof('  > open')
    if g:context.presenter == 'nvim-float'
        let popup = context#popup#nvim#open()
    elseif g:context.presenter == 'vim-popup'
        let popup = context#popup#vim#open()
    endif

    " NOTE: we use a non breaking space here again before the buffer name
    let border = ' *' .g:context.char_border . '* '
    let tag = s:context_buffer_name
    " TODO: remove these
    call matchadd(g:context.highlight_border, border, 10, -1, {'window': popup})
    call matchadd(g:context.highlight_tag,    tag,    10, -1, {'window': popup})

    let buf = winbufnr(popup)
    " call setbufvar(buf, '&syntax', &syntax)

    return popup
endfunction

function! s:close(popup) abort
    call context#util#echof('  > close')
    if g:context.presenter == 'nvim-float'
        call context#popup#nvim#close(a:popup)
    elseif g:context.presenter == 'vim-popup'
        call context#popup#vim#close(a:popup)
    endif
endfunction

function! s:get_border_line(winid, indent) abort
    let c = getwinvar(a:winid, 'context')
    let indent = a:indent ? c.indent : 0

    let new_top_line = w:context.top_line + len(w:context.lines)
    " TODO: use 0 or -1 in second []? which one is more natural/useful?
    " TODO: +1 or not in the end? (to avoid zeros)
    let n = new_top_line - w:context.lines[-1][0].number

    " NOTE: we use a non breaking space after the border chars because there
    " can be some display issues in the Kitty terminal with a normal space

    let line_len = c.size_w - c.padding - indent - 1
    let border_char = g:context.char_border
    if g:context.show_tag
        let line_len -= len(s:context_buffer_name) + 1
        let border_text = repeat(g:context.char_border, line_len)
        " here the NB space belongs to the tag part (for minor highlighting reasons)
        let tag_text = ' ' . s:context_buffer_name . ' '
        return [
                    \ context#line#make_highlight(0, n, border_char, indent, border_text, g:context.highlight_border),
                    \ context#line#make_highlight(0, n, border_char, indent, tag_text,    g:context.highlight_tag)
                    \ ]
    endif

    " here the NB space belongs to the border part
    let border_text = repeat(g:context.char_border, line_len) . ' '
    return [context#line#make_highlight(0, n, border_char, indent, border_text, g:context.highlight_border)]
endfunction

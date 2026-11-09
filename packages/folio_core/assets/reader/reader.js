import '../foliate/view.js'

const THEMES = {
    light: { bg: '#ffffff', fg: '#1b1b1b', link: '#1a5fb4' },
    sepia: { bg: '#f4ecd8', fg: '#433422', link: '#7a4b12' },
    dark: { bg: '#121212', fg: '#d8d8d8', link: '#8ab4f8' },
}

const style = { theme: 'light', fontSize: 100, lineHeight: 1.5, margin: 32 }
let view = null

const bridgeReady = new Promise(resolve => {
    if (window.flutter_inappwebview?.callHandler) resolve()
    else window.addEventListener('flutterInAppWebViewPlatformReady', resolve, { once: true })
})

const send = async (name, data) => {
    await bridgeReady
    return window.flutter_inappwebview.callHandler(name, data)
}

const bookCSS = () => {
    const t = THEMES[style.theme] ?? THEMES.light
    return `
    html {
        color-scheme: ${style.theme === 'dark' ? 'dark' : 'light'};
        background: ${t.bg} !important;
        color: ${t.fg} !important;
        font-size: ${style.fontSize}% !important;
    }
    body { background: transparent !important; color: inherit !important; }
    p, li, blockquote, dd, div {
        line-height: ${style.lineHeight};
        -webkit-hyphens: auto;
        hyphens: auto;
        widows: 2;
        orphans: 2;
    }
    a:link, a:visited { color: ${t.link}; }
    img, svg { max-width: 100%; height: auto; }
    pre { white-space: pre-wrap !important; }
    `
}

const applyStyle = () => {
    const t = THEMES[style.theme] ?? THEMES.light
    document.documentElement.style.setProperty('--folio-bg', t.bg)
    if (!view?.renderer) return
    view.renderer.setAttribute('margin', `${style.margin}px`)
    view.renderer.setAttribute('gap', '6%')
    view.renderer.setAttribute('max-inline-size', '720px')
    view.renderer.setStyles?.(bookCSS())
}

const flattenToc = (items, depth = 0, out = []) => {
    for (const item of items ?? []) {
        out.push({ label: (item.label ?? '').trim(), href: item.href, depth })
        if (item.subitems?.length) flattenToc(item.subitems, depth + 1, out)
    }
    return out
}

const handleTap = (event, doc) => {
    if (doc.getSelection()?.toString()) return
    if (event.target.closest?.('a[href]')) return
    let x = event.clientX
    try {
        const frame = doc.defaultView.frameElement
        if (frame) x = frame.getBoundingClientRect().left + event.clientX
    } catch { /* cross-origin frame: fall back to clientX */ }
    const width = window.innerWidth
    if (x < width * 0.3) view.prev()
    else if (x > width * 0.7) view.next()
    else send('toggleChrome')
}

window.folio = {
    async open(url, lastCfi, options) {
        try {
            Object.assign(style, options ?? {})
            const res = await fetch(url)
            if (!res.ok) throw new Error(`Could not load book (${res.status})`)
            const blob = await res.blob()
            const name = url.split('/').pop() || 'book.epub'
            const file = new File([blob], name, { type: 'application/epub+zip' })

            view = document.createElement('foliate-view')
            document.body.append(view)
            await view.open(file)
            view.renderer.setAttribute('flow', 'paginated')
            applyStyle()

            view.addEventListener('load', ({ detail: { doc } }) => {
                doc.addEventListener('click', e => handleTap(e, doc))
            })
            view.addEventListener('relocate', ({ detail }) => {
                send('relocate', {
                    cfi: detail.cfi ?? null,
                    fraction: detail.fraction ?? 0,
                    chapter: detail.tocItem?.label?.trim() ?? null,
                    location: detail.location
                        ? { current: detail.location.current, total: detail.location.total }
                        : null,
                })
            })

            await view.init({ lastLocation: lastCfi || null })
            const meta = view.book.metadata ?? {}
            send('ready', {
                toc: flattenToc(view.book.toc),
                title: typeof meta.title === 'string' ? meta.title : null,
            })
        } catch (e) {
            send('error', String(e?.message ?? e))
        }
    },
    next() { view?.next() },
    prev() { view?.prev() },
    goTo(target) { return view?.goTo(target) },
    goToFraction(fraction) { return view?.goToFraction(fraction) },
    setStyle(options) {
        Object.assign(style, options ?? {})
        applyStyle()
    },
}

send('jsReady')

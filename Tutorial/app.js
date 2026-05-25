// AppleTrace tutorial — progressive enhancement only; the page works without JS.
(function () {
    'use strict';

    // Copy buttons on code blocks.
    document.querySelectorAll('.code').forEach(function (block) {
        var head = block.querySelector('.code-head');
        if (!head) return;
        var btn = head.querySelector('.copy');
        if (!btn) return;
        btn.addEventListener('click', function () {
            var code = block.querySelector('pre');
            if (!code) return;
            navigator.clipboard.writeText(code.innerText).then(function () {
                var prev = btn.textContent;
                btn.textContent = 'copied';
                setTimeout(function () { btn.textContent = prev; }, 1400);
            });
        });
    });

    // Mobile sidebar toggle.
    var sidebar = document.querySelector('.sidebar');
    var menuBtn = document.querySelector('.menu-btn');
    var scrim = document.querySelector('.scrim');
    function close() { sidebar && sidebar.classList.remove('open'); scrim && scrim.classList.remove('show'); }
    if (menuBtn && sidebar) {
        menuBtn.addEventListener('click', function () {
            sidebar.classList.toggle('open');
            scrim && scrim.classList.toggle('show');
        });
    }
    if (scrim) scrim.addEventListener('click', close);
    sidebar && sidebar.querySelectorAll('a').forEach(function (a) { a.addEventListener('click', close); });

    // Scroll-spy: highlight the sidebar link for the section in view.
    var links = Array.prototype.slice.call(document.querySelectorAll('.sidebar a[href^="#"]'));
    var map = {};
    links.forEach(function (a) {
        var id = a.getAttribute('href').slice(1);
        var sec = document.getElementById(id);
        if (sec) map[id] = a;
    });
    var sections = Object.keys(map).map(function (id) { return document.getElementById(id); });
    if ('IntersectionObserver' in window && sections.length) {
        var current = null;
        var obs = new IntersectionObserver(function (entries) {
            entries.forEach(function (e) {
                if (e.isIntersecting) current = e.target.id;
            });
            links.forEach(function (a) { a.classList.remove('active'); });
            if (current && map[current]) map[current].classList.add('active');
        }, { rootMargin: '-20% 0px -70% 0px', threshold: 0 });
        sections.forEach(function (s) { obs.observe(s); });
    }
})();

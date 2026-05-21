(function(global) {
    'use strict';

    var navLinks = [
        { href: 'index.html', label: 'All Models' },
        { href: 'free.html', label: 'Free' },
        { href: 'paid.html', label: 'Paid' },
        { href: 'local.html', label: 'Local' },
        { href: 'compare.html', label: 'Compare' }
    ];

    function createNav(currentPage) {
        currentPage = currentPage || 'index.html';
        var nav = document.createElement('nav');
        nav.className = 'main-nav';
        
        var ul = document.createElement('ul');
        navLinks.forEach(function(link) {
            var li = document.createElement('li');
            var a = document.createElement('a');
            a.href = link.href;
            a.textContent = link.label;
            if (link.href === currentPage || (currentPage === '' && link.href === 'index.html')) {
                a.className = 'active';
            }
            li.appendChild(a);
            ul.appendChild(li);
        });
        nav.appendChild(ul);
        
        var mobileToggle = document.createElement('button');
        mobileToggle.className = 'nav-toggle';
        mobileToggle.setAttribute('aria-label', 'Toggle navigation');
        mobileToggle.textContent = '☰';
        nav.insertBefore(mobileToggle, nav.firstChild);
        
        mobileToggle.addEventListener('click', function() {
            nav.classList.toggle('open');
        });
        
        return nav;
    }

    function initNav(containerId, currentPage) {
        var container = document.getElementById(containerId);
        if (!container) return;
        var nav = createNav(currentPage);
        container.appendChild(nav);
    }

    global.AIMTNav = {
        createNav: createNav,
        initNav: initNav,
        links: navLinks
    };

})(window);
(function() {
    'use strict';

    var models = [];
    var state = {
        provider: null,
        search: '',
        sortCol: 'contextPerCent',
        sortDir: 'desc',
        selectedModel: null,
        dataPolicy: null
    };

    function showFatalError(msg) {
        var el = document.getElementById('table-container');
        if (!el) return;
        el.innerHTML = '<div class="error-block" role="alert"><p><strong>Failed to load model data.</strong></p><p>' + AIMT.escHtml(msg || '') + '</p></div>';
    }

    window.__renderTable = function(allModels, st) {
        var el = document.getElementById('table-container');
        if (!el) return;
        
        var paidModels = allModels.filter(function(m) { return !m.isFree; });
        var rows = AIMT.filterModels(paidModels, { provider: st.provider, search: st.search, dataPolicy: st.dataPolicy });
        rows = AIMT.sortModels(rows, st.sortCol, st.sortDir);

        el.innerHTML = '<div class="result-count">' + rows.length + ' paid models</div>';

        var th = function(col, label) {
            var stateClass = st.sortCol === col ? (' sorted ' + st.sortDir) : '';
            return '<th data-col="' + AIMT.escHtml(col) + '" class="sortable' + stateClass + '">' + AIMT.escHtml(label) + AIMT.getSortArrow(col, st.sortCol, st.sortDir) + '</th>';
        };

        var html = '<table class="model-table"><thead><tr>';
        html += th('name', 'Model');
        html += th('provider', 'Provider');
        html += th('context_length', 'Context');
        html += th('prompt_price', 'Prompt$/M');
        html += th('completion_price', 'Completion$/M');
        html += th('contextPerCent', 'Ctx/Cent');
        html += '<th>Policy</th><th>Mod.</th><th>ID</th></tr></thead><tbody>';
        rows.forEach(function(m) {
            var isSelected = st.selectedModel === m.id;
            html += '<tr class="model-row' + (isSelected ? ' selected' : '') + '" data-id="' + AIMT.escHtml(m.id || '') + '">';
            html += '<td class="model-name">' + AIMT.escHtml(m.name || m.id || '') + '</td>';
            html += '<td class="model-provider">' + AIMT.escHtml(m.provider || '') + '</td>';
            html += '<td class="model-context">' + AIMT.formatCtx(m.context_length) + '</td>';
            html += '<td class="model-prompt">' + AIMT.formatPrice(m.pricing && m.pricing.prompt) + '</td>';
            html += '<td class="model-completion">' + AIMT.formatPrice(m.pricing && m.pricing.completion) + '</td>';
            html += '<td class="model-cpc">' + AIMT.formatCtxPerCent(m.contextPerCent) + '</td>';
            html += '<td class="model-policy">' + AIMT.escHtml(m.data_policy_level || 'unknown') + '</td>';
            html += '<td class="model-mod">' + (m.is_moderated ? '✓' : '') + '</td>';
            html += '<td><button class="copy-model-id" data-id="' + AIMT.escHtml(m.id || '') + '">Copy</button></td>';
            html += '</tr>';
        });
        html += '</tbody></table>';
        el.insertAdjacentHTML('beforeend', html);

        el.querySelectorAll('th.sortable').forEach(function(th) {
            th.addEventListener('click', function() {
                var col = th.dataset.col;
                if (st.sortCol === col) {
                    st.sortDir = st.sortDir === 'asc' ? 'desc' : 'asc';
                } else {
                    st.sortCol = col;
                    st.sortDir = 'asc';
                }
                AIMT.writeHash(state);
                render();
            });
        });

        el.querySelectorAll('tr.model-row').forEach(function(row) {
            row.addEventListener('click', function() {
                var id = row.dataset.id;
                st.selectedModel = st.selectedModel === id ? null : id;
                AIMT.writeHash(state);
                render();
            });
        });

        el.querySelectorAll('.copy-model-id').forEach(function(btn) {
            btn.addEventListener('click', async function(ev) {
                ev.stopPropagation();
                var ok = await AIMT.copyText(btn.dataset.id || '');
                btn.textContent = ok ? 'Copied' : 'Copy';
                setTimeout(function() { btn.textContent = 'Copy'; }, 900);
            });
        });
    };

    function initThemeButton() {
        var btn = document.getElementById('theme-toggle');
        if (!btn || btn.dataset.initialized) return;
        btn.dataset.initialized = '1';
        btn.addEventListener('click', function() {
            AIMT.toggleTheme();
            updateThemeIcon();
        });
    }

    function updateThemeIcon() {
        var btn = document.getElementById('theme-toggle');
        if (!btn) return;
        btn.textContent = (document.documentElement.dataset.theme === 'light') ? '☀️' : '🌙';
    }

    window.__renderTheme = function(st) {
        initThemeButton();
        updateThemeIcon();
    };

    function populateProviderDropdown() {
        var sel = document.getElementById('provider-filter');
        if (!sel) return;
        var paidModels = models.filter(function(m) { return !m.isFree; });
        var current = sel.value;
        sel.innerHTML = '<option value="">All Providers</option>';
        AIMT.getUniqueProviders(paidModels).forEach(function(p) {
            var opt = document.createElement('option');
            opt.value = p;
            opt.textContent = p;
            sel.appendChild(opt);
        });
        sel.value = current;
    }

    function render() {
        if (typeof window.__renderTable === 'function') {
            try { window.__renderTable(models, state); } catch (e) { console.error(e); }
        }
        if (typeof window.__renderTheme === 'function') {
            try { window.__renderTheme(state); } catch (e) { console.error(e); }
        }
    }

    function initSearch() {
        var inp = document.getElementById('model-search');
        if (inp) {
            inp.value = state.search || '';
            inp.addEventListener('input', AIMT.debounce(function() {
                state.search = inp.value;
                AIMT.writeHash(state);
                render();
            }, AIMT.DEBOUNCE_MS));
        }

        var sel = document.getElementById('provider-filter');
        if (sel) {
            sel.addEventListener('change', function() {
                state.provider = sel.value || null;
                AIMT.writeHash(state);
                render();
            });
        }

        var policy = document.getElementById('policy-filter');
        if (policy) {
            policy.addEventListener('change', function() {
                state.dataPolicy = policy.value || null;
                AIMT.writeHash(state);
                render();
            });
        }
    }

    function applyHashToState() {
        var parsed = AIMT.parseHash();
        state.provider = parsed.provider;
        state.search = parsed.search;
        state.sortCol = parsed.sortCol || 'contextPerCent';
        state.sortDir = parsed.sortDir || 'desc';
        state.selectedModel = parsed.selectedModel;
        state.dataPolicy = parsed.dataPolicy;
    }

    window.addEventListener('hashchange', function() { applyHashToState(); render(); });
    window.addEventListener('popstate', function() { applyHashToState(); render(); });

    document.addEventListener('DOMContentLoaded', async function() {
        AIMT.initTheme();
        applyHashToState();
        initSearch();
        try {
            var data = await AIMT.loadData('./data/');
            models = data.models;
            populateProviderDropdown();
            var policy = document.getElementById('policy-filter');
            if (policy) policy.value = state.dataPolicy || '';
        } catch (e) {
            showFatalError(e.message);
            return;
        }
        render();
    });
})();

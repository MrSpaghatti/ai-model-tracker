(function() {
    'use strict';

    var models = [];
    var history = null;
    var state = {
        provider: null,
        search: '',
        sortCol: 'contextPerCent',
        sortDir: 'desc',
        selectedModel: null,
        minPrice: undefined,
        maxPrice: undefined,
        modality: null,
        free: undefined,
        moderated: undefined
    };

    function showFatalError(msg) {
        var el = document.getElementById('table-container');
        if (!el) return;
        el.innerHTML = '<div class="error-block" role="alert"><p><strong>Failed to load model data.</strong></p><p>' + AIMT.escHtml(msg || '') + '</p><p>View <a href="../FREE_MODELS.md">static markdown pages</a>.</p></div>';
    }

    window.__renderTable = function(allModels, st) {
        var el = document.getElementById('table-container');
        if (!el) return;
        
        var filters = {
            provider: st.provider,
            search: st.search,
            minPrice: st.minPrice,
            maxPrice: st.maxPrice,
            modality: st.modality,
            free: st.free,
            moderated: st.moderated
        };
        var rows = AIMT.filterModels(allModels, filters);
        rows = AIMT.sortModels(rows, st.sortCol, st.sortDir);

        if (st.provider) {
            var prices = rows.map(function(m) { return AIMT.toNumber(m.pricing && m.pricing.prompt) || 0; }).filter(function(p) { return p > 0; });
            var minP = prices.length ? Math.min.apply(null, prices) : 0;
            var maxP = prices.length ? Math.max.apply(null, prices) : 0;
            el.innerHTML = '<div class="provider-header"><span>' + AIMT.escHtml(st.provider) + '</span><span class="provider-count">' + rows.length + ' models</span><button id="clear-provider">Clear filter</button></div>';
            el.innerHTML += '<div class="provider-stats">Price range: ' + AIMT.formatPrice(minP) + ' - ' + AIMT.formatPrice(maxP) + '</div>';
            var btn = document.getElementById('clear-provider');
            if (btn) btn.addEventListener('click', function() { state.provider = null; AIMT.writeHash(state); render(); });
        } else {
            el.innerHTML = '';
        }

        var th = function(col, label) {
            return '<th data-col="' + AIMT.escHtml(col) + '" class="sortable' + (st.sortCol === col ? ' sorted' : '') + '">' + AIMT.escHtml(label) + AIMT.getSortArrow(col, st.sortCol, st.sortDir) + '</th>';
        };

        var html = '<table class="model-table"><thead><tr>';
        html += th('name', 'Model');
        html += th('provider', 'Provider');
        html += th('context_length', 'Context');
        html += th('prompt_price', 'Prompt$/M');
        html += th('completion_price', 'Completion$/M');
        html += th('contextPerCent', 'Ctx/Cent');
        html += '<th>Mod.</th></tr></thead><tbody>';
        rows.forEach(function(m) {
            var isSelected = st.selectedModel === m.id;
            html += '<tr class="model-row' + (isSelected ? ' selected' : '') + '" data-id="' + AIMT.escHtml(m.id || '') + '">';
            html += '<td class="model-name">' + AIMT.escHtml(m.name || m.id || '') + '</td>';
            html += '<td class="model-provider">' + AIMT.escHtml(m.provider || '') + '</td>';
            html += '<td class="model-context" data-sort="' + (AIMT.toNumber(m.context_length) || 0) + '">' + AIMT.formatCtx(m.context_length) + '</td>';
            html += '<td class="model-prompt" data-sort="' + (AIMT.toNumber(m.pricing && m.pricing.prompt) || -1) + '">' + AIMT.formatPrice(m.pricing && m.pricing.prompt) + '</td>';
            html += '<td class="model-completion" data-sort="' + (AIMT.toNumber(m.pricing && m.pricing.completion) || -1) + '">' + AIMT.formatPrice(m.pricing && m.pricing.completion) + '</td>';
            html += '<td class="model-cpc" data-sort="' + (m.contextPerCent !== undefined ? m.contextPerCent : -Infinity) + '">' + AIMT.formatCtxPerCent(m.contextPerCent) + '</td>';
            html += '<td class="model-mod">' + (m.is_moderated ? '✓' : '') + '</td>';
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
                if (st.selectedModel === id) {
                    st.selectedModel = null;
                } else {
                    st.selectedModel = id;
                }
                AIMT.writeHash(state);
                render();
            });
        });
    };

    window.__renderChart = function(hist, st) {
        var el = document.getElementById('chart-container');
        if (!el) return;
        if (!st.selectedModel || !hist || !hist.entries || !hist.entries.length) {
            el.innerHTML = '<div class="chart-placeholder">Select a model to view price history</div>';
            return;
        }

        var modelEntries = hist.entries.filter(function(e) { return e.model_id === st.selectedModel; })
            .sort(function(a, b) { return a.from_date.localeCompare(b.from_date); });

        if (!modelEntries.length) {
            el.innerHTML = '<div class="chart-placeholder">No price history for this model</div>';
            return;
        }

        if (modelEntries.length < 2) {
            el.innerHTML = '<div class="chart-placeholder">Only one data point — history will accumulate over time</div>';
            return;
        }

        var timestamps = modelEntries.map(function(e) { return new Date(e.from_date).getTime() / 1000; });
        var promptPrices = modelEntries.map(function(e) { return Number(e.prompt_price) * 1e6; });
        var completionPrices = modelEntries.map(function(e) { return Number(e.completion_price) * 1e6; });

        el.innerHTML = '<div class="chart-header"><span>' + AIMT.escHtml(st.selectedModel) + '</span><button id="close-chart">×</button></div><div id="chart"></div><div id="chart-legend"></div>';

        var closeBtn = document.getElementById('close-chart');
        if (closeBtn) {
            closeBtn.addEventListener('click', function() {
                st.selectedModel = null;
                AIMT.writeHash(state);
                render();
            });
        }

        if (window.uPlot) {
            var isDark = document.documentElement.dataset.theme !== 'light';
            var gridColor = isDark ? '#30363d' : '#d0d7de';
            var textColor = isDark ? '#e6edf3' : '#1f2328';
            var promptColor = '#58a6ff';
            var completionColor = '#3fb950';

            var opts = {
                title: 'Price History ($/M tokens)',
                width: Math.max(300, el.clientWidth - 32 || 800),
                height: 300,
                scales: { y: { distr: 3 } },
                axes: [
                    {}, { stroke: textColor, grid: { stroke: gridColor }, values: function(u, vals) { return vals.map(function(v) { return '$' + v.toFixed(4); }); } }
                ],
                series: [
                    {},
                    { label: 'Prompt', stroke: promptColor, width: 2 },
                    { label: 'Completion', stroke: completionColor, width: 2 }
                ],
                legend: { show: true }
            };

            new window.uPlot(opts, [timestamps, promptPrices, completionPrices], document.getElementById('chart'));

            var legend = document.getElementById('chart-legend');
            var last = modelEntries[modelEntries.length - 1];
            legend.innerHTML = '<span class="legend-item"><span style="color:' + promptColor + '">●</span> Prompt: ' + AIMT.formatPrice(last.prompt_price) + '</span> <span class="legend-item"><span style="color:' + completionColor + '">●</span> Completion: ' + AIMT.formatPrice(last.completion_price) + '</span>';
        }
    };

    window.__renderTheme = function(st) {
        var btn = document.getElementById('theme-toggle');
        if (!btn) return;
        btn.textContent = (document.documentElement.dataset.theme === 'light') ? '☀️' : '🌙';
        btn.addEventListener('click', function() {
            AIMT.toggleTheme();
            window.__renderTheme(st);
            if (st.selectedModel) window.__renderChart(history, st);
        });
    };

    function populateProviderDropdown() {
        var sel = document.getElementById('provider-filter');
        if (!sel) return;
        var current = sel.value;
        sel.innerHTML = '<option value="">All Providers</option>';
        AIMT.getUniqueProviders(models).forEach(function(p) {
            var opt = document.createElement('option');
            opt.value = p;
            opt.textContent = p;
            sel.appendChild(opt);
        });
        sel.value = current;
    }

    function render() {
        if (typeof window.__renderTable === 'function') {
            try { window.__renderTable(models, state); } catch (e) { console.error('renderTable:', e); }
        }
        if (typeof window.__renderChart === 'function') {
            try { window.__renderChart(history, state); } catch (e) { console.error('renderChart:', e); }
        }
        if (typeof window.__renderTheme === 'function') {
            try { window.__renderTheme(state); } catch (e) { console.error('renderTheme:', e); }
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
    }

    function applyHashToState() {
        var parsed = AIMT.parseHash();
        state.provider = parsed.provider;
        state.search = parsed.search;
        state.sortCol = parsed.sortCol;
        state.sortDir = parsed.sortDir;
        state.selectedModel = parsed.selectedModel;
        state.minPrice = parsed.minPrice;
        state.maxPrice = parsed.maxPrice;
        state.modality = parsed.modality;
        state.free = parsed.free;
        state.moderated = parsed.moderated;
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
            history = data.history;
            var lastEl = document.getElementById('last-updated');
            if (lastEl) lastEl.textContent = AIMT.formatTimestamp(data.generatedAt);
            populateProviderDropdown();
        } catch (e) {
            showFatalError(e.message);
            return;
        }
        render();
    });

    try {
        window.render = render;
    } catch (e) {}
})();
(function () {
    'use strict';

    const DEBOUNCE_MS = 150;

    let models = [];
    let history = null;
    const state = {
        provider: null,
        search: '',
        sortCol: 'contextPerCent',
        sortDir: 'desc',
        selectedModel: null
    };

    function escHtml(s) {
        return String(s).replace(/[&<>"']/g, function (c) {
            return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c];
        });
    }

    function toNumber(v) {
        if (v === null || v === undefined || v === '') return null;
        const n = Number(v);
        return Number.isFinite(n) ? n : null;
    }

    function computeContextPerCent(model) {
        const pricing = model && model.pricing;
        if (!pricing) return -Infinity;
        const promptPrice = toNumber(pricing.prompt);
        const ctx = toNumber(model.context_length);
        if (promptPrice === null || ctx === null) return -Infinity;
        if (promptPrice === 0) return Infinity;
        return ctx / (promptPrice * 100);
    }

    function formatPrice(v) {
        if (v === null || v === undefined || v === '') return 'N/A';
        const n = Number(v);
        if (!Number.isFinite(n)) return 'N/A';
        if (n === 0) return 'Free';
        return '$' + (n * 1e6).toFixed(4) + '/M';
    }

    function formatCtx(n) {
        if (n === null || n === undefined) return 'N/A';
        return Number(n).toLocaleString();
    }

    function formatCtxPerCent(v) {
        if (!Number.isFinite(v)) return v === Infinity ? '∞' : 'N/A';
        return v.toLocaleString(undefined, {maximumFractionDigits:0});
    }

    function formatTimestamp(iso) {
        if (!iso) return '';
        const d = new Date(iso);
        if (Number.isNaN(d.getTime())) return String(iso);
        try {
            return d.toLocaleString('en-US',{timeZone:'UTC',dateStyle:'medium',timeStyle:'short'}) + ' UTC';
        } catch (_e) {
            return d.toISOString();
        }
    }

    function showFatalError(msg) {
        const el = document.getElementById('table-container');
        if (!el) return;
        el.innerHTML = '<div class="error-block" role="alert"><p><strong>Failed to load model data.</strong></p><p>' + escHtml(msg || '') + '</p><p>View <a href="../FREE_MODELS.md">static markdown pages</a>.</p></div>';
    }

    function getUniqueProviders() {
        const provs = {};
        models.forEach(function(m) { if (m.provider) provs[m.provider] = true; });
        return Object.keys(provs).sort();
    }

    function populateProviderDropdown() {
        const sel = document.getElementById('provider-filter');
        if (!sel) return;
        const current = sel.value;
        sel.innerHTML = '<option value="">All Providers</option>';
        getUniqueProviders().forEach(function(p) {
            const opt = document.createElement('option');
            opt.value = p;
            opt.textContent = p;
            sel.appendChild(opt);
        });
        sel.value = current;
    }

    function filterAndSort(arr, st) {
        let filtered = arr;
        if (st.provider) {
            filtered = filtered.filter(function(m) { return m.provider === st.provider; });
        }
        if (st.search) {
            const q = st.search.toLowerCase();
            filtered = filtered.filter(function(m) {
                return (m.id && m.id.toLowerCase().includes(q)) ||
                       (m.name && m.name.toLowerCase().includes(q)) ||
                       (m.provider && m.provider.toLowerCase().includes(q));
            });
        }
        filtered.sort(function(a, b) {
            let av, bv;
            switch (st.sortCol) {
                case 'name': av = (a.name || '').toLowerCase(); bv = (b.name || '').toLowerCase(); break;
                case 'provider': av = (a.provider || '').toLowerCase(); bv = (b.provider || '').toLowerCase(); break;
                case 'context_length': av = toNumber(a.context_length) || -Infinity; bv = toNumber(b.context_length) || -Infinity; break;
                case 'prompt_price': av = toNumber(a.pricing && a.pricing.prompt) || -Infinity; bv = toNumber(b.pricing && b.pricing.prompt) || -Infinity; break;
                case 'completion_price': av = toNumber(a.pricing && a.pricing.completion) || -Infinity; bv = toNumber(b.pricing && b.pricing.completion) || -Infinity; break;
                default: av = a.contextPerCent; bv = b.contextPerCent;
            }
            if (av < bv) return st.sortDir === 'asc' ? -1 : 1;
            if (av > bv) return st.sortDir === 'asc' ? 1 : -1;
            return 0;
        });
        return filtered;
    }

    function getSortArrow(col, st) {
        if (st.sortCol !== col) return '';
        return st.sortDir === 'asc' ? ' ▲' : ' ▼';
    }

    function debounce(fn, ms) {
        let t;
        return function() {
            clearTimeout(t);
            t = setTimeout(function() { fn.apply(null, arguments); }, ms);
        };
    }

    window.__renderTable = function(allModels, st) {
        const el = document.getElementById('table-container');
        if (!el) return;
        const rows = filterAndSort(allModels, st);

        if (st.provider) {
            const prices = rows.map(function(m) { return toNumber(m.pricing && m.pricing.prompt) || 0; }).filter(function(p) { return p > 0; });
            const minP = prices.length ? Math.min.apply(null, prices) : 0;
            const maxP = prices.length ? Math.max.apply(null, prices) : 0;
            el.innerHTML = '<div class="provider-header"><span>' + escHtml(st.provider) + '</span><span class="provider-count">' + rows.length + ' models</span><button id="clear-provider">Clear filter</button></div>';
            el.innerHTML += '<div class="provider-stats">Price range: ' + formatPrice(minP) + ' - ' + formatPrice(maxP) + '</div>';
            const btn = document.getElementById('clear-provider');
            if (btn) btn.addEventListener('click', function() { state.provider = null; writeHash(); render(); });
        } else {
            el.innerHTML = '';
        }

        const th = function(col, label) {
            return '<th data-col="' + escHtml(col) + '" class="sortable' + (st.sortCol === col ? ' sorted' : '') + '">' + escHtml(label) + getSortArrow(col, st) + '</th>';
        };

        let html = '<table class="model-table"><thead><tr>';
        html += th('name', 'Model');
        html += th('provider', 'Provider');
        html += th('context_length', 'Context');
        html += th('prompt_price', 'Prompt$/M');
        html += th('completion_price', 'Completion$/M');
        html += th('contextPerCent', 'Ctx/Cent');
        html += '<th>Mod.</th></tr></thead><tbody>';
        rows.forEach(function(m) {
            const isSelected = st.selectedModel === m.id;
            html += '<tr class="model-row' + (isSelected ? ' selected' : '') + '" data-id="' + escHtml(m.id || '') + '">';
            html += '<td class="model-name">' + escHtml(m.name || m.id || '') + '</td>';
            html += '<td class="model-provider">' + escHtml(m.provider || '') + '</td>';
            html += '<td class="model-context" data-sort="' + (toNumber(m.context_length) || 0) + '">' + formatCtx(m.context_length) + '</td>';
            html += '<td class="model-prompt" data-sort="' + (toNumber(m.pricing && m.pricing.prompt) || -1) + '">' + formatPrice(m.pricing && m.pricing.prompt) + '</td>';
            html += '<td class="model-completion" data-sort="' + (toNumber(m.pricing && m.pricing.completion) || -1) + '">' + formatPrice(m.pricing && m.pricing.completion) + '</td>';
            html += '<td class="model-cpc" data-sort="' + (m.contextPerCent !== undefined ? m.contextPerCent : -Infinity) + '">' + formatCtxPerCent(m.contextPerCent) + '</td>';
            html += '<td class="model-mod">' + (m.is_moderated ? '✓' : '') + '</td>';
            html += '</tr>';
        });
        html += '</tbody></table>';

        el.insertAdjacentHTML('beforeend', html);

        el.querySelectorAll('th.sortable').forEach(function(th) {
            th.addEventListener('click', function() {
                const col = th.dataset.col;
                if (st.sortCol === col) {
                    st.sortDir = st.sortDir === 'asc' ? 'desc' : 'asc';
                } else {
                    st.sortCol = col;
                    st.sortDir = 'asc';
                }
                writeHash();
                render();
            });
        });

        el.querySelectorAll('tr.model-row').forEach(function(row) {
            row.addEventListener('click', function() {
                const id = row.dataset.id;
                if (st.selectedModel === id) {
                    st.selectedModel = null;
                } else {
                    st.selectedModel = id;
                }
                writeHash();
                render();
            });
        });
    };

    window.__renderChart = function(hist, st) {
        const el = document.getElementById('chart-container');
        if (!el) return;
        if (!st.selectedModel || !hist || !hist.entries || !hist.entries.length) {
            el.innerHTML = '<div class="chart-placeholder">Select a model to view price history</div>';
            return;
        }

        const modelEntries = hist.entries.filter(function(e) { return e.model_id === st.selectedModel; })
            .sort(function(a, b) { return a.from_date.localeCompare(b.from_date); });

        if (!modelEntries.length) {
            el.innerHTML = '<div class="chart-placeholder">No price history for this model</div>';
            return;
        }

        if (modelEntries.length < 2) {
            el.innerHTML = '<div class="chart-placeholder">Only one data point — history will accumulate over time</div>';
            return;
        }

        const timestamps = modelEntries.map(function(e) { return new Date(e.from_date).getTime() / 1000; });
        const promptPrices = modelEntries.map(function(e) { return Number(e.prompt_price) * 1e6; });
        const completionPrices = modelEntries.map(function(e) { return Number(e.completion_price) * 1e6; });

        el.innerHTML = '<div class="chart-header"><span>' + escHtml(st.selectedModel) + '</span><button id="close-chart">×</button></div><div id="chart"></div><div id="chart-legend"></div>';

        const closeBtn = document.getElementById('close-chart');
        if (closeBtn) {
            closeBtn.addEventListener('click', function() {
                st.selectedModel = null;
                writeHash();
                render();
            });
        }

        if (window.uPlot) {
            const isDark = document.documentElement.dataset.theme !== 'light';
            const gridColor = isDark ? '#30363d' : '#d0d7de';
            const textColor = isDark ? '#e6edf3' : '#1f2328';
            const promptColor = '#58a6ff';
            const completionColor = '#3fb950';

            const opts = {
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

            const legend = document.getElementById('chart-legend');
            const last = modelEntries[modelEntries.length - 1];
            legend.innerHTML = '<span class="legend-item"><span style="color:' + promptColor + '">●</span> Prompt: ' + formatPrice(last.prompt_price) + '</span> <span class="legend-item"><span style="color:' + completionColor + '">●</span> Completion: ' + formatPrice(last.completion_price) + '</span>';
        }
    };

    window.__renderTheme = function(st) {
        const btn = document.getElementById('theme-toggle');
        if (!btn) return;
        btn.textContent = (document.documentElement.dataset.theme === 'light') ? '☀️' : '🌙';
        btn.addEventListener('click', function() {
            const cur = document.documentElement.dataset.theme;
            const next = cur === 'light' ? 'dark' : 'light';
            document.documentElement.dataset.theme = next;
            try { localStorage.setItem('theme', next); } catch (_e) {}
            window.__renderTheme(st);
            if (st.selectedModel) window.__renderChart(history, st);
        });
    };

    async function loadData() {
        let currentRes, historyRes;
        try {
            const results = await Promise.all([
                fetch('./data/current.json'),
                fetch('./data/history.json').catch(function() { return null; })
            ]);
            currentRes = results[0];
            historyRes = results[1];
        } catch (_e) {
            showFatalError('Network error loading data');
            return false;
        }

        if (!currentRes || !currentRes.ok) {
            showFatalError('Failed to fetch model data');
            return false;
        }

        let current;
        try {
            current = await currentRes.json();
        } catch (_e) {
            showFatalError('Invalid JSON response');
            return false;
        }

        const rawModels = (current && Array.isArray(current.models)) ? current.models : [];
        models = rawModels.map(function(m) {
            const id = m.id || '';
            const provider = (typeof id === 'string' && id.indexOf('/') !== -1) ? id.split('/')[0] : (m.provider || '');
            return Object.assign({}, m, { provider: provider, contextPerCent: computeContextPerCent(m) });
        });

        if (historyRes && historyRes.ok) {
            try { history = await historyRes.json(); }
            catch (_e) { history = { entries: [] }; }
        } else {
            history = { entries: [] };
        }

        const lastEl = document.getElementById('last-updated');
        if (lastEl) lastEl.textContent = formatTimestamp(current && current.generated_at);

        populateProviderDropdown();
        return true;
    }

    function parseHash() {
        const raw = (location.hash || '').replace(/^#/, '');
        const params = new URLSearchParams(raw);
        return {
            provider: params.get('provider') || null,
            search: params.get('search') || '',
            sortCol: params.get('sort') || 'contextPerCent',
            sortDir: params.get('dir') === 'asc' ? 'asc' : 'desc',
            selectedModel: params.get('model') || null
        };
    }

    function pushHashToHistory(hash) {
        if (window.history && typeof window.history.pushState === 'function') {
            window.history.pushState(null, '', location.pathname + location.search + hash);
        } else {
            location.hash = hash;
        }
    }

    function writeHash() {
        const params = new URLSearchParams();
        if (state.provider) params.set('provider', state.provider);
        if (state.search) params.set('search', state.search);
        if (state.sortCol && state.sortCol !== 'contextPerCent') params.set('sort', state.sortCol);
        if (state.sortDir && state.sortDir !== 'desc') params.set('dir', state.sortDir);
        if (state.selectedModel) params.set('model', state.selectedModel);
        const str = params.toString();
        const next = str ? ('#' + str) : '';
        if (next !== location.hash) {
            try { pushHashToHistory(next); } catch (_e) { location.hash = next; }
        }
    }

    function applyHashToState() {
        const parsed = parseHash();
        state.provider = parsed.provider;
        state.search = parsed.search;
        state.sortCol = parsed.sortCol;
        state.sortDir = parsed.sortDir;
        state.selectedModel = parsed.selectedModel;
    }

    function render() {
        if (typeof window.__renderTable === 'function') {
            try { window.__renderTable(models, state); } catch (_e) { console.error('renderTable:', _e); }
        }
        if (typeof window.__renderChart === 'function') {
            try { window.__renderChart(history, state); } catch (_e) { console.error('renderChart:', _e); }
        }
        if (typeof window.__renderTheme === 'function') {
            try { window.__renderTheme(state); } catch (_e) { console.error('renderTheme:', _e); }
        }
    }

    function initTheme() {
        try {
            const stored = localStorage.getItem('theme');
            if (stored) {
                document.documentElement.dataset.theme = stored;
                return;
            }
        } catch (_e) {}
        if (window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches) {
            document.documentElement.dataset.theme = 'light';
        }
    }

    function initSearch() {
        const inp = document.getElementById('model-search');
        if (inp) {
            inp.value = state.search || '';
            inp.addEventListener('input', debounce(function() {
                state.search = inp.value;
                writeHash();
                render();
            }, DEBOUNCE_MS));
        }

        const sel = document.getElementById('provider-filter');
        if (sel) {
            sel.addEventListener('change', function() {
                state.provider = sel.value || null;
                writeHash();
                render();
            });
        }
    }

    window.addEventListener('hashchange', function() { applyHashToState(); render(); });
    window.addEventListener('popstate', function() { applyHashToState(); render(); });

    document.addEventListener('DOMContentLoaded', async function() {
        initTheme();
        applyHashToState();
        initSearch();
        await loadData();
        render();
    });

    try {
        window.render = render;
        window.writeHash = writeHash;
    } catch (_e) {}
})();
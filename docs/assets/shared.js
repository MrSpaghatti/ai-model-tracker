// Shared utilities for AI Model Tracker
(function(global) {
    'use strict';

    const DEBOUNCE_MS = 150;

    // ============ Utility Functions ============

    function escHtml(s) {
        return String(s).replace(/[&<>"']/g, function(c) {
            return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c];
        });
    }

    function toNumber(v) {
        if (v === null || v === undefined || v === '') return null;
        const n = Number(v);
        return Number.isFinite(n) ? n : null;
    }

    function debounce(fn, ms) {
        let t;
        return function() {
            clearTimeout(t);
            t = setTimeout(function() { fn.apply(null, arguments); }, ms);
        };
    }

    // ============ Price-change detection ============

    // The 30-day delta is computed by the generator (src/main.nim ->
    // docs/data/changes.json) and attached to each model by loadData. It used to
    // be derived here from history.json, which meant every page load pulled
    // 1.7 MB just to render one column.
    var CHANGE_EPSILON_PCT = 0.5;   // below this it rounds to noise, not a change

    function formatDelta(chg) {
        if (!chg) return '<span class="delta delta-none">\u2014</span>';
        var pct = chg.pct;

        if (pct === null) {
            if (chg.to > 0) {
                return '<span class="delta delta-up" title="' + escHtml(changeTitle(chg)) +
                    '">new</span>';
            }
            return '<span class="delta delta-none">\u2014</span>';
        }

        var detail = changeTitle(chg);
        if (chg.to === 0 && chg.from > 0) {
            return '<span class="delta delta-down" title="' + escHtml(detail) + '">now free</span>';
        }
        if (Math.abs(pct) < CHANGE_EPSILON_PCT) {
            return '<span class="delta delta-none" title="' + escHtml(detail) + '">\u2014</span>';
        }

        var down = pct < 0;
        return '<span class="delta ' + (down ? 'delta-down' : 'delta-up') + '" title="' +
            escHtml(detail) + '">' + (down ? '\u25bc ' : '\u25b2 ') +
            Math.abs(pct).toFixed(Math.abs(pct) < 10 ? 1 : 0) + '%</span>';
    }

    function changeTitle(chg) {
        var lines = ['Prompt ' + formatPrice(chg.from / 1e6) + ' \u2192 ' + formatPrice(chg.to / 1e6)];
        if (chg.fromCompletion !== chg.toCompletion) {
            lines.push('Completion ' + formatPrice(chg.fromCompletion / 1e6) + ' \u2192 ' +
                formatPrice(chg.toCompletion / 1e6));
        }
        lines.push('vs ' + (chg.compareDate || chg.fromDate.slice(0, 10)) + ' (' +
            chg.spanDays + (chg.spanDays === 1 ? ' day' : ' days') + ' ago)');
        return lines.join('\n');
    }

    // ============ Formatting Functions ============

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

    // Data freshness is a trust signal, not decoration: the site served
    // three-month-old prices with no indication at all while the refresh was
    // silently failing. Stamp the age on every page and shout when it is old.
    var STALE_HOURS = 36;

    function applyFreshness(iso) {
        if (!iso) return;
        var el = document.getElementById('last-updated');
        if (el) {
            el.textContent = formatTimestamp(iso);
            el.setAttribute('title', iso);
        }
        var ageHours = (Date.now() - new Date(iso).getTime()) / 3600000;
        if (!isFinite(ageHours) || ageHours < STALE_HOURS) return;
        var main = document.querySelector('main');
        if (!main || document.getElementById('stale-banner')) return;
        var days = Math.floor(ageHours / 24);
        var age = days >= 1
            ? days + (days === 1 ? ' day' : ' days')
            : Math.max(1, Math.floor(ageHours)) + ' hours';
        var banner = document.createElement('div');
        banner.id = 'stale-banner';
        banner.className = 'stale-banner';
        banner.innerHTML = '<strong>Stale data.</strong> Last successful refresh ' +
            escHtml(formatTimestamp(iso)) + ' (' + age + ' ago) \u2014 prices below may no longer be current.';
        main.insertBefore(banner, main.firstChild);
    }

    // ============ Model Computation Functions ============

    function computeContextPerCent(model) {
        const pricing = model && model.pricing;
        if (!pricing) return -Infinity;
        const promptPrice = toNumber(pricing.prompt);
        const ctx = toNumber(model.context_length);
        if (promptPrice === null || ctx === null) return -Infinity;
        if (promptPrice === 0) return Infinity;
        return ctx / (promptPrice * 100);
    }

    function computeProvider(model) {
        const id = model.id || '';
        if (typeof id === 'string' && id.indexOf('/') !== -1) {
            return id.split('/')[0];
        }
        return model.provider || '';
    }

    function isFreeModel(model) {
        const p = model && model.pricing;
        return p && (toNumber(p.prompt) === 0 || toNumber(p.prompt) === null) && 
               (toNumber(p.completion) === 0 || toNumber(p.completion) === null);
    }

    // ============ Filtering Functions ============

    function getUniqueProviders(models) {
        const provs = {};
        models.forEach(function(m) { 
            if (m.provider) provs[m.provider] = true; 
        });
        return Object.keys(provs).sort();
    }

    function getUniqueModalities(models) {
        const mods = {};
        models.forEach(function(m) {
            const arch = m.architecture;
            if (arch && arch.modality) {
                const parts = arch.modality.split('->')[0].split('+');
                parts.forEach(function(p) { mods[p.trim()] = true; });
            }
        });
        return Object.keys(mods).sort();
    }

    function filterModels(models, filters) {
        let result = models;
        
        // Provider filter
        if (filters.provider) {
            result = result.filter(function(m) { return m.provider === filters.provider; });
        }
        
        // Search filter
        if (filters.search) {
            const q = filters.search.toLowerCase();
            result = result.filter(function(m) {
                return (m.id && m.id.toLowerCase().includes(q)) ||
                       (m.name && m.name.toLowerCase().includes(q)) ||
                       (m.provider && m.provider.toLowerCase().includes(q)) ||
                       (m.architecture && m.architecture.modality && m.architecture.modality.toLowerCase().includes(q));
            });
        }
        
        // Price range filter (prompt price in $ per million)
        if (filters.minPrice !== undefined) {
            result = result.filter(function(m) {
                const p = toNumber(m.pricing && m.pricing.prompt);
                return p === null || p >= filters.minPrice;
            });
        }
        if (filters.maxPrice !== undefined) {
            result = result.filter(function(m) {
                const p = toNumber(m.pricing && m.pricing.prompt);
                return p === null || p <= filters.maxPrice;
            });
        }
        
        // Context length filter
        if (filters.minContext !== undefined) {
            result = result.filter(function(m) {
                const c = toNumber(m.context_length);
                return c === null || c >= filters.minContext;
            });
        }
        if (filters.maxContext !== undefined) {
            result = result.filter(function(m) {
                const c = toNumber(m.context_length);
                return c === null || c <= filters.maxContext;
            });
        }
        
        // Modality filter
        if (filters.modality) {
            result = result.filter(function(m) {
                const arch = m.architecture;
                if (!arch || !arch.modality) return false;
                return arch.modality.includes(filters.modality);
            });
        }
        
        // Free/Paid filter
        if (filters.free !== undefined) {
            result = result.filter(function(m) {
                return isFreeModel(m) === filters.free;
            });
        }
        
        // Moderation filter
        if (filters.moderated !== undefined) {
            result = result.filter(function(m) {
                return (!!m.is_moderated) === filters.moderated;
            });
        }
        
        // Capability filter (based on supported_parameters)
        if (filters.capability) {
            const cap = filters.capability.toLowerCase();
            result = result.filter(function(m) {
                const params = m.supported_parameters || [];
                return params.some(function(p) { return p.toLowerCase().includes(cap); });
            });
        }
        
        return result;
    }

    // ============ Sorting Functions ============

    function getSortArrow(col, sortCol, sortDir) {
        if (sortCol !== col) return '';
        return sortDir === 'asc' ? ' ▲' : ' ▼';
    }

    function sortModels(models, sortCol, sortDir) {
        const sorted = models.slice();
        sorted.sort(function(a, b) {
            let av, bv;
            switch (sortCol) {
                case 'name': 
                    av = (a.name || '').toLowerCase(); 
                    bv = (b.name || '').toLowerCase(); 
                    break;
                case 'provider': 
                    av = (a.provider || '').toLowerCase(); 
                    bv = (b.provider || '').toLowerCase(); 
                    break;
                case 'context_length': 
                    av = toNumber(a.context_length) || -Infinity; 
                    bv = toNumber(b.context_length) || -Infinity; 
                    break;
                case 'prompt_price': 
                    av = toNumber(a.pricing && a.pricing.prompt) || -Infinity; 
                    bv = toNumber(b.pricing && b.pricing.prompt) || -Infinity; 
                    break;
                case 'completion_price': 
                    av = toNumber(a.pricing && a.pricing.completion) || -Infinity; 
                    bv = toNumber(b.pricing && b.pricing.completion) || -Infinity; 
                    break;
                case 'contextPerCent':
                    av = a.contextPerCent !== undefined ? a.contextPerCent : -Infinity;
                    bv = b.contextPerCent !== undefined ? b.contextPerCent : -Infinity;
                    break;
                case 'created':
                    av = toNumber(a.created) || 0;
                    bv = toNumber(b.created) || 0;
                    break;
                case 'delta':
                    // Ascending puts the biggest price cuts first. Models with no
                    // comparable history must sink to the bottom in BOTH
                    // directions, so the sentinel has to flip with sortDir —
                    // a fixed Infinity floats them to the top when descending.
                    av = (a.priceChange && a.priceChange.pct !== null)
                        ? a.priceChange.pct : (sortDir === 'asc' ? Infinity : -Infinity);
                    bv = (b.priceChange && b.priceChange.pct !== null)
                        ? b.priceChange.pct : (sortDir === 'asc' ? Infinity : -Infinity);
                    break;
                default: 
                    av = a.contextPerCent; 
                    bv = b.contextPerCent;
            }
            if (av < bv) return sortDir === 'asc' ? -1 : 1;
            if (av > bv) return sortDir === 'asc' ? 1 : -1;
            return 0;
        });
        return sorted;
    }

    // ============ URL State Functions ============

    function parseHash() {
        const raw = (location.hash || '').replace(/^#/, '');
        const params = new URLSearchParams(raw);
        return {
            provider: params.get('provider') || null,
            search: params.get('search') || '',
            sortCol: params.get('sort') || 'contextPerCent',
            sortDir: params.get('dir') === 'asc' ? 'asc' : 'desc',
            selectedModel: params.get('model') || null,
            // Extended filters
            minPrice: params.get('minPrice') ? parseFloat(params.get('minPrice')) : undefined,
            maxPrice: params.get('maxPrice') ? parseFloat(params.get('maxPrice')) : undefined,
            modality: params.get('modality') || null,
            free: params.get('free') === 'true' ? true : params.get('free') === 'false' ? false : undefined,
            moderated: params.get('mod') === 'true' ? true : params.get('mod') === 'false' ? false : undefined,
        };
    }

    function writeHash(state) {
        const params = new URLSearchParams();
        if (state.provider) params.set('provider', state.provider);
        if (state.search) params.set('search', state.search);
        if (state.sortCol && state.sortCol !== 'contextPerCent') params.set('sort', state.sortCol);
        if (state.sortDir && state.sortDir !== 'desc') params.set('dir', state.sortDir);
        if (state.selectedModel) params.set('model', state.selectedModel);
        // Extended filters
        if (state.minPrice !== undefined) params.set('minPrice', state.minPrice);
        if (state.maxPrice !== undefined) params.set('maxPrice', state.maxPrice);
        if (state.modality) params.set('modality', state.modality);
        if (state.free !== undefined) params.set('free', state.free);
        if (state.moderated !== undefined) params.set('mod', state.moderated);
        
        const str = params.toString();
        const next = str ? ('#' + str) : '';
        if (next !== location.hash) {
            try {
                if (window.history && typeof window.history.pushState === 'function') {
                    window.history.pushState(null, '', location.pathname + location.search + next);
                } else {
                    location.hash = next;
                }
            } catch (_e) {
                location.hash = next;
            }
        }
    }

    // ============ Price-history chart (shared by all pages) ============

    // ============ Collection heartbeat ============
    // history.json records price *changes*, so a flat line means either "the
    // price held steady" or "nothing was collecting data" — the two are
    // indistinguishable, and the Aug-Nov outage drew as months of stability.
    // The generator appends a record to heartbeat.json on every run it finishes,
    // so a gap between consecutive runs is a period nobody was watching.
    var HEARTBEAT_GAP_SECONDS = 36 * 3600;   // matches STALE_HOURS
    var heartbeatRuns = null;                // seconds, sorted; null = not loaded
    var heartbeatPromise = null;

    function loadHeartbeat() {
        if (heartbeatPromise) return heartbeatPromise;
        heartbeatPromise = fetch('data/heartbeat.json', { cache: 'no-cache' })
            .then(function(r) { return r.ok ? r.json() : null; })
            .then(function(j) {
                heartbeatRuns = ((j && j.runs) || [])
                    .map(function(r) { return new Date(r.at).getTime() / 1000; })
                    .filter(function(t) { return isFinite(t); })
                    .sort(function(a, b) { return a - b; });
                return heartbeatRuns;
            })
            .catch(function() { heartbeatRuns = []; return heartbeatRuns; });
        return heartbeatPromise;
    }

    function heartbeatGaps() {
        var out = [];
        if (!heartbeatRuns || heartbeatRuns.length < 2) return out;
        for (var i = 1; i < heartbeatRuns.length; i++) {
            var a = heartbeatRuns[i - 1], b = heartbeatRuns[i];
            if (b - a > HEARTBEAT_GAP_SECONDS) out.push([a, b]);
        }
        return out;
    }

    // #chart-container is display:none in style.css and only becomes visible
    // with the .active class, so every path through here has to set it.
    // opts: { height, title, onClose }
    function renderChart(hist, st, opts) {
        opts = opts || {};
        var el = document.getElementById(opts.containerId || 'chart-container');
        if (!el) return;

        if (!st.selectedModel) {
            el.classList.remove('active');
            el.innerHTML = '';
            return;
        }
        el.classList.add('active');

        if (!hist) {
            // loadData no longer ships history.json; fetch it on first chart open
            // and re-enter once it lands.
            el.innerHTML = '<div class="chart-placeholder">Loading price history…</div>';
            loadHistory(opts.dataPath).then(function(h) {
                if (st.selectedModel) renderChart(h, st, opts);
            });
            return;
        }

        function placeholder(msg) {
            el.innerHTML = '<div class="chart-placeholder">' + msg + '</div>';
        }

        if (!hist || !hist.entries || !hist.entries.length) return placeholder('No price history available');

        var modelEntries = hist.entries
            .filter(function(e) { return e.model_id === st.selectedModel; })
            .sort(function(a, b) { return a.from_date.localeCompare(b.from_date); });

        if (!modelEntries.length) return placeholder('No price history for this model');
        if (modelEntries.length < 2) return placeholder('Only one data point — history will accumulate over time');
        // A log axis cannot represent $0; a fully free model would draw a flat
        // line pinned to the axis floor. Say it in words instead.
        var anyPaid = modelEntries.some(function(e) {
            return Number(e.prompt_price) > 0 || Number(e.completion_price) > 0;
        });
        if (!anyPaid) return placeholder('This model is free — prompt and completion are $0/M.');
        if (!window.uPlot) return placeholder('Chart library failed to load');

        var timestamps = [];
        // Prices are stored per token; the chart reads better per million.
        var promptPrices = [];
        var completionPrices = [];

        // Prices are step functions, not ramps: a recorded price holds until the
        // next recorded change. Joining points with a straight line draws a fake
        // gradual slope between distant ones — z-ai/glm-5.2 went $0.76 -> $0.006/M,
        // which as a diagonal reads as months of drift instead of one cliff.
        // Emitting each segment's end point again at the OLD value makes that
        // hold-then-jump shape out of the plain linear path (uPlot's own
        // paths.stepped renders no path at all in this setup).
        for (var i = 0; i < modelEntries.length; i++) {
            var e = modelEntries[i];
            var t = new Date(e.from_date).getTime() / 1000;
            var pp = Number(e.prompt_price) * 1e6;
            var cp = Number(e.completion_price) * 1e6;
            timestamps.push(t);
            promptPrices.push(pp);
            completionPrices.push(cp);
            var next = modelEntries[i + 1];
            if (next) {
                var nt = new Date(next.from_date).getTime() / 1000;
                if (nt > t) {
                    // Hold this price flat up to the moment the next one starts.
                    timestamps.push(nt);
                    promptPrices.push(pp);
                    completionPrices.push(cp);
                }
            }
        }
        var height = opts.height || 300;

        // Declared before `series` below: `var` hoists but does not initialise, so
        // building the series first would give stroke: undefined and draw nothing.
        var isDark = document.documentElement.dataset.theme !== 'light';
        var promptColor = '#58a6ff';
        var completionColor = '#3fb950';

        var series = [
            {},
            { label: 'Prompt', stroke: promptColor, width: 2 },
            { label: 'Completion', stroke: completionColor, width: 2 }
        ];

        el.innerHTML = '<div class="chart-header"><span>' + escHtml(st.selectedModel) +
            '</span><button id="close-chart" aria-label="Close chart">×</button></div>' +
            '<div id="chart"></div><div id="chart-legend"></div><div id="chart-note" class="chart-note"></div>';

        var closeBtn = document.getElementById('close-chart');
        if (closeBtn) {
            closeBtn.addEventListener('click', function() {
                st.selectedModel = null;
                writeHash(st);
                if (typeof opts.onClose === 'function') opts.onClose();
            });
        }

        var chartEl = document.getElementById('chart');

        // Paint the unmonitored stretches behind the price lines. uPlot's draw
        // hook runs after the grid and before the series, so the bands sit
        // underneath the data instead of covering it.
        var drawGaps = function(u) {
            var gaps = heartbeatGaps();
            if (!gaps.length) return;
            var ctx = u.ctx;
            var bb = u.bbox;
            ctx.save();
            ctx.fillStyle = isDark ? 'rgba(248,81,73,0.13)' : 'rgba(207,34,46,0.09)';
            for (var i = 0; i < gaps.length; i++) {
                var x0 = u.valToPos(gaps[i][0], 'x', true);
                var x1 = u.valToPos(gaps[i][1], 'x', true);
                if (x1 < bb.left || x0 > bb.left + bb.width) continue;
                x0 = Math.max(x0, bb.left);
                x1 = Math.min(x1, bb.left + bb.width);
                if (x1 - x0 < 1) continue;
                ctx.fillRect(x0, bb.top, x1 - x0, bb.height);
            }
            ctx.restore();
        };

        var u = new window.uPlot({
            title: opts.title || 'Price History ($/M tokens)',
            // Fall back to 800 only when the container has no measurable width;
            // `Math.max(300, w - 32 || 800)` collapsed to 300 because -32 is truthy.
            width: Math.max(300, (el.clientWidth || 800) - 32),
            height: height,
            scales: { y: { distr: 3, log: 10 } },
            axes: [
                {},
                {
                    size: 76,
                    stroke: isDark ? '#e6edf3' : '#1f2328',
                    grid: { stroke: isDark ? '#30363d' : '#d0d7de' },
                    // Decade ticks only. uPlot's default log splits add 8 minor
                    // ticks per decade, which smears into an unreadable stack
                    // when prices span 8 orders of magnitude.
                    splits: function(_u, _ai, min, max) {
                        var out = [];
                        var v = Math.pow(10, Math.floor(Math.log(min) / Math.LN10));
                        for (var i = 0; i < 24 && v <= max * 1.0001; i++) {
                            if (v >= min * 0.9999) out.push(v);
                            v *= 10;
                        }
                        return out.length ? out : [min, max];
                    },
                    values: function(_u, vals) {
                        return vals.map(function(raw) {
                            var n = Number(raw);
                            if (!isFinite(n)) return '';
                            if (n === 0) return '$0';
                            var a = Math.abs(n);
                            if (a >= 0.0001) {
                                var d = a >= 1 ? 2 : a >= 0.01 ? 3 : 5;
                                return '$' + n.toFixed(d);
                            }
                            return '$' + n.toExponential(1);
                        });
                    }
                }
            ],
            series: series,
            legend: { show: true },
            hooks: { draw: [drawGaps] }
        }, [timestamps, promptPrices, completionPrices], chartEl);

        // The heartbeat loads separately from the price data, so the first paint
        // has no bands; redraw once it arrives.
        loadHeartbeat().then(function() {
            var gaps = heartbeatGaps();
            if (!gaps.length) return;
            u.redraw();
            var note = document.getElementById('chart-note');
            if (note) {
                note.textContent = 'Shaded bands = no data collected (the collector was not running).';
            }
        });

        var resize = function() {
            if (chartEl && chartEl.clientWidth) u.setSize({ width: chartEl.clientWidth, height: height });
        };
        window.removeEventListener('resize', resize);
        window.addEventListener('resize', resize);

        var legend = document.getElementById('chart-legend');
        if (legend) {
            var last = modelEntries[modelEntries.length - 1];
            legend.innerHTML = '<span class="legend-item"><span style="color:' + promptColor + '">●</span> Prompt: ' +
                formatPrice(last.prompt_price) + '</span> <span class="legend-item"><span style="color:' + completionColor +
                '">●</span> Completion: ' + formatPrice(last.completion_price) + '</span>';
        }
    }

    // ============ Data Loading Functions ============

    // history.json is 1.7 MB and only the chart needs it, so it is fetched on
    // the first chart open instead of on every page load.
    var historyPromise = null;
    function loadHistory(dataPath) {
        if (historyPromise) return historyPromise;
        historyPromise = fetch((dataPath || './data/') + 'history.json')
            .then(function(r) { return r.ok ? r.json() : { entries: [] }; })
            .catch(function() { return { entries: [] }; });
        return historyPromise;
    }

    async function loadData(dataPath) {
        dataPath = dataPath || './data/';
        let currentRes, changesRes;
        try {
            const results = await Promise.all([
                fetch(dataPath + 'current.json'),
                fetch(dataPath + 'changes.json').catch(function() { return null; })
            ]);
            currentRes = results[0];
            changesRes = results[1];
        } catch (_e) {
            throw new Error('Network error loading data');
        }

        if (!currentRes || !currentRes.ok) {
            throw new Error('Failed to fetch model data');
        }

        let current;
        try {
            current = await currentRes.json();
        } catch (_e) {
            throw new Error('Invalid JSON response');
        }

        const rawModels = (current && Array.isArray(current.models)) ? current.models : [];
        const models = rawModels.map(function(m) {
            return Object.assign({}, m, { 
                provider: computeProvider(m), 
                contextPerCent: computeContextPerCent(m),
                isFree: isFreeModel(m)
            });
        });

        // Deltas are precomputed by the generator (changes.json, ~85 KB) rather
        // than derived in the browser from history.json (1.7 MB) on every load.
        let changes = {};
        if (changesRes && changesRes.ok) {
            try { changes = (await changesRes.json()).changes || {}; }
            catch (_e) {}
        }
        models.forEach(function(m) {
            m.priceChange = changes[m.id] || null;
        });

        applyFreshness(current.generated_at);

        return {
            models: models,
            // Fetched lazily by renderChart; see loadHistory().
            history: null,
            generatedAt: current.generated_at
        };
    }

    // ============ Theme Functions ============

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

    function toggleTheme() {
        const cur = document.documentElement.dataset.theme;
        const next = cur === 'light' ? 'dark' : 'light';
        document.documentElement.dataset.theme = next;
        try { localStorage.setItem('theme', next); } catch (_e) {}
        return next;
    }

    // ============ Export ============

    global.AIMT = {
        // Constants
        DEBOUNCE_MS: DEBOUNCE_MS,
        
        // Utils
        escHtml: escHtml,
        toNumber: toNumber,
        debounce: debounce,
        
        // Formatting
        formatPrice: formatPrice,
        formatCtx: formatCtx,
        formatCtxPerCent: formatCtxPerCent,
        formatTimestamp: formatTimestamp,
        
        // Model computation
        computeContextPerCent: computeContextPerCent,
        computeProvider: computeProvider,
        isFreeModel: isFreeModel,

        // Price changes
        formatDelta: formatDelta,
        
        // Filtering
        getUniqueProviders: getUniqueProviders,
        getUniqueModalities: getUniqueModalities,
        filterModels: filterModels,
        
        // Sorting
        getSortArrow: getSortArrow,
        sortModels: sortModels,
        
        // URL State
        parseHash: parseHash,
        writeHash: writeHash,
        
        // Data
        loadData: loadData,
        applyFreshness: applyFreshness,

        // Chart
        renderChart: renderChart,
        
        // Theme
        initTheme: initTheme,
        toggleTheme: toggleTheme
    };

})(window);
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

        if (filters.dataPolicy) {
            result = result.filter(function(m) {
                return (m.data_policy_level || '').toLowerCase() === filters.dataPolicy.toLowerCase();
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
            dataPolicy: params.get('policy') || null,
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
        if (state.dataPolicy) params.set('policy', state.dataPolicy);
        
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

    // ============ Data Loading Functions ============

    async function loadData(dataPath) {
        dataPath = dataPath || './data/';
        let currentRes, historyRes;
        try {
            const results = await Promise.all([
                fetch(dataPath + 'current.json'),
                fetch(dataPath + 'history.json').catch(function() { return null; })
            ]);
            currentRes = results[0];
            historyRes = results[1];
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

        let history = { entries: [] };
        if (historyRes && historyRes.ok) {
            try { history = await historyRes.json(); }
            catch (_e) {}
        }

        return {
            models: models,
            history: history,
            generatedAt: current.generated_at,
            changes: current.changes || { new_models: [], removed_models: [], price_changes: [], biggest_movers: [] },
            providerStats: current.provider_stats || []
        };
    }

    async function copyText(text) {
        if (!text) return false;
        try {
            if (navigator.clipboard && navigator.clipboard.writeText) {
                await navigator.clipboard.writeText(text);
                return true;
            }
        } catch (_e) {}
        return false;
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
        copyText: copyText,
        
        // Theme
        initTheme: initTheme,
        toggleTheme: toggleTheme
    };

})(window);
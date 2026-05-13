(function() {
    'use strict';

    var models = [];
    var selectedIds = [];
    var MAX_COMPARE = 4;

    function updateSelectedDisplay() {
        var el = document.getElementById('selected-models');
        if (!el) return;

        if (selectedIds.length === 0) {
            el.innerHTML = '<p class="hint">Select up to ' + MAX_COMPARE + ' models to compare</p>';
            return;
        }

        var html = '<div class="selected-chips">';
        selectedIds.forEach(function(id) {
            var model = models.filter(function(m) { return m.id === id; })[0];
            if (model) {
                html += '<span class="model-chip selected">';
                html += AIMT.escHtml(model.name || model.id);
                html += ' <button class="remove-btn" data-id="' + AIMT.escHtml(id) + '">×</button>';
                html += '</span>';
            }
        });
        html += '</div>';
        el.innerHTML = html;

        el.querySelectorAll('.remove-btn').forEach(function(btn) {
            btn.addEventListener('click', function() {
                var id = btn.dataset.id;
                selectedIds = selectedIds.filter(function(i) { return i !== id; });
                updateSelectedDisplay();
                renderComparison();
            });
        });
    }

    function renderComparison() {
        var el = document.getElementById('comparison-container');
        if (!el) return;

        if (selectedIds.length < 2) {
            el.innerHTML = '<p class="hint">Select at least 2 models to see comparison</p>';
            return;
        }

        var selected = selectedIds.map(function(id) {
            return models.filter(function(m) { return m.id === id; })[0];
        }).filter(Boolean);

        var html = '<table class="compare-table"><thead><tr>';
        html += '<th>Property</th>';
        selected.forEach(function(m) {
            html += '<th>' + AIMT.escHtml(m.name || m.id) + '</th>';
        });
        html += '</tr></thead><tbody>';

        var rows = [
            { label: 'Provider', get: function(m) { return m.provider || 'N/A'; } },
            { label: 'Context Length', get: function(m) { return AIMT.formatCtx(m.context_length); } },
            { label: 'Prompt Price', get: function(m) { return AIMT.formatPrice(m.pricing && m.pricing.prompt); } },
            { label: 'Completion Price', get: function(m) { return AIMT.formatPrice(m.pricing && m.pricing.completion); } },
            { label: 'Context/Cent', get: function(m) { return AIMT.formatCtxPerCent(m.contextPerCent); } },
            { label: 'Modality', get: function(m) { return m.architecture && m.architecture.modality ? m.architecture.modality : 'N/A'; } },
            { label: 'Moderated', get: function(m) { return m.is_moderated ? 'Yes' : 'No'; } },
            { label: 'Best For', get: function(m) { 
                var params = m.supported_parameters || [];
                var caps = [];
                if (params.some(function(p) { return p.includes('tools'); })) caps.push('Tools');
                if (params.some(function(p) { return p.includes('reasoning'); })) caps.push('Reasoning');
                if (params.some(function(p) { return p.includes('temperature'); })) caps.push('Creative');
                return caps.length ? caps.join(', ') : 'N/A';
            }}
        ];

        rows.forEach(function(row) {
            html += '<tr><td class="compare-label">' + row.label + '</td>';
            selected.forEach(function(m) {
                html += '<td>' + row.get(m) + '</td>';
            });
            html += '</tr>';
        });

        html += '</tbody></table>';

        html += '<div class="compare-actions">';
        html += '<button id="share-btn" class="share-btn">Share Comparison</button>';
        html += '<button id="clear-btn">Clear All</button>';
        html += '</div>';

        el.innerHTML = html;

        document.getElementById('share-btn').addEventListener('click', function() {
            var url = location.origin + location.pathname + '?compare=' + selectedIds.join(',');
            navigator.clipboard.writeText(url).then(function() {
                alert('Comparison URL copied to clipboard!');
            }).catch(function() {
                prompt('Copy this URL:', url);
            });
        });

        document.getElementById('clear-btn').addEventListener('click', function() {
            selectedIds = [];
            updateSelectedDisplay();
            renderComparison();
        });
    }

    function renderSearchResults(query) {
        var el = document.getElementById('search-results');
        if (!el) return;

        if (!query || query.length < 2) {
            el.innerHTML = '';
            return;
        }

        var q = query.toLowerCase();
        var matches = models.filter(function(m) {
            return (m.id && m.id.toLowerCase().includes(q)) ||
                   (m.name && m.name.toLowerCase().includes(q)) ||
                   (m.provider && m.provider.toLowerCase().includes(q));
        }).slice(0, 10);

        if (matches.length === 0) {
            el.innerHTML = '<p class="hint">No models found</p>';
            return;
        }

        var html = '<ul class="search-list">';
        matches.forEach(function(m) {
            var isSelected = selectedIds.indexOf(m.id) !== -1;
            var disabled = !isSelected && selectedIds.length >= MAX_COMPARE;
            html += '<li class="' + (isSelected ? 'selected' : '') + ' ' + (disabled ? 'disabled' : '') + '">';
            html += '<button data-id="' + AIMT.escHtml(m.id) + '" ' + (disabled ? 'disabled' : '') + '>';
            html += AIMT.escHtml(m.name || m.id);
            html += ' <small>' + AIMT.escHtml(m.provider || '') + '</small>';
            html += '</button></li>';
        });
        html += '</ul>';
        el.innerHTML = html;

        el.querySelectorAll('button:not([disabled])').forEach(function(btn) {
            btn.addEventListener('click', function() {
                var id = btn.dataset.id;
                if (selectedIds.indexOf(id) === -1 && selectedIds.length < MAX_COMPARE) {
                    selectedIds.push(id);
                }
                updateSelectedDisplay();
                renderComparison();
                document.getElementById('model-search').value = '';
                el.innerHTML = '';
            });
        });
    }

    function initSearch() {
        var inp = document.getElementById('model-search');
        if (inp) {
            inp.addEventListener('input', AIMT.debounce(function() {
                renderSearchResults(inp.value);
            }, AIMT.DEBOUNCE_MS));
        }
    }

    function loadFromURL() {
        var params = new URLSearchParams(location.search);
        var compare = params.get('compare');
        if (compare) {
            selectedIds = compare.split(',').filter(Boolean);
        }
    }

    document.addEventListener('DOMContentLoaded', async function() {
        AIMT.initTheme();
        loadFromURL();
        initSearch();
        
        try {
            var data = await AIMT.loadData('./data/');
            models = data.models;
            updateSelectedDisplay();
            renderComparison();
        } catch (e) {
            console.error('Failed to load models:', e);
        }
    });
})();
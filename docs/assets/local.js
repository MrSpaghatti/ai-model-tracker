(function() {
    'use strict';

    var localModels = [];

    function parseVRAM(vramStr) {
        if (!vramStr || vramStr === 'N/A' || vramStr === '-') return null;
        var match = vramStr.match(/(\d+)/);
        return match ? parseInt(match[1]) : null;
    }

    function formatVRAM(vram) {
        return vram ? vram + ' GB' : 'N/A';
    }

    function getBestForBadge(bestFor) {
        if (!bestFor || !bestFor.length) return '';
        var badges = bestFor.map(function(b) {
            return '<span class="badge badge-' + b.trim().toLowerCase().replace(' ', '-') + '">' + AIMT.escHtml(b.trim()) + '</span>';
        });
        return badges.join(' ');
    }

    function renderTable(models) {
        var el = document.getElementById('table-container');
        if (!el) return;

        el.innerHTML = '<div class="result-count">' + models.length + ' local models</div>';

        var html = '<table class="model-table local-table"><thead><tr>';
        html += '<th>Model</th>';
        html += '<th>Size</th>';
        html += '<th>FP16</th>';
        html += '<th>FP8</th>';
        html += '<th>4-bit</th>';
        html += '<th>Best For</th>';
        html += '<th>Ollama</th>';
        html += '</tr></thead><tbody>';

        models.forEach(function(m) {
            html += '<tr data-id="' + AIMT.escHtml(m.id) + '">';
            html += '<td class="model-name"><strong>' + AIMT.escHtml(m.name) + '</strong>';
            if (m.notes) html += '<br><small style="color:var(--fg-muted)">' + AIMT.escHtml(m.notes) + '</small>';
            html += '</td>';
            html += '<td class="model-size">' + AIMT.escHtml(m.size) + '</td>';
            html += '<td class="model-vram" data-vram="' + (parseVRAM(m.vram_fp16) || 0) + '">' + formatVRAM(parseVRAM(m.vram_fp16)) + '</td>';
            html += '<td class="model-vram" data-vram="' + (parseVRAM(m.vram_fp8) || 0) + '">' + formatVRAM(parseVRAM(m.vram_fp8)) + '</td>';
            html += '<td class="model-vram" data-vram="' + (parseVRAM(m.vram_4bit) || 0) + '">' + formatVRAM(parseVRAM(m.vram_4bit)) + '</td>';
            html += '<td class="model-tags">' + getBestForBadge(m.best_for) + '</td>';
            html += '<td class="model-ollama"><code>' + AIMT.escHtml(m.ollama_cmd) + '</code></td>';
            html += '</tr>';
        });

        html += '</tbody></table>';
        el.insertAdjacentHTML('beforeend', html);
    }

    function calculateVRAM() {
        var memoryInput = document.getElementById('gpu-memory');
        var quantSelect = document.getElementById('quantization');
        var resultsEl = document.getElementById('vram-results');
        
        if (!memoryInput || !quantSelect || !resultsEl) return;

        var gpuMemory = parseInt(memoryInput.value);
        var quant = quantSelect.value;

        if (!gpuMemory || gpuMemory < 2) {
            resultsEl.innerHTML = '<p class="error">Please enter a valid GPU memory amount.</p>';
            return;
        }

        var vramKey = quant === 'fp16' ? 'vram_fp16' : quant === 'fp8' ? 'vram_fp8' : 'vram_4bit';
        
        var compatible = localModels.filter(function(m) {
            var vram = parseVRAM(m[vramKey]);
            return vram !== null && vram <= gpuMemory;
        }).sort(function(a, b) {
            var vramA = parseVRAM(a[vramKey]) || 0;
            var vramB = parseVRAM(b[vramKey]) || 0;
            return vramB - vramA;
        });

        var tooLarge = localModels.filter(function(m) {
            var vram = parseVRAM(m[vramKey]);
            return vram !== null && vram > gpuMemory;
        });

        var html = '<h3>Compatible with ' + gpuMemory + ' GB (' + quant.toUpperCase() + ')</h3>';
        
        if (compatible.length > 0) {
            html += '<div class="compatible-models">';
            compatible.forEach(function(m) {
                var vram = parseVRAM(m[vramKey]);
                var margin = gpuMemory - vram;
                html += '<div class="model-card">';
                html += '<strong>' + AIMT.escHtml(m.name) + '</strong> (' + vram + ' GB)';
                html += '<br><small>' + margin + ' GB headroom</small>';
                html += '</div>';
            });
            html += '</div>';
        } else {
            html += '<p>No models fit within ' + gpuMemory + ' GB ' + quant.toUpperCase() + '.</p>';
        }

        if (tooLarge.length > 0 && compatible.length < 5) {
            html += '<h4 style="margin-top:1rem">Too large for ' + gpuMemory + ' GB:</h4>';
            html += '<div class="too-large-models">';
            tooLarge.slice(0, 5).forEach(function(m) {
                var vram = parseVRAM(m[vramKey]);
                html += '<span class="model-chip">' + AIMT.escHtml(m.name) + ' (' + vram + ' GB)</span>';
            });
            html += '</div>';
        }

        resultsEl.innerHTML = html;
    }

    function init() {
        var calcBtn = document.getElementById('calc-btn');
        if (calcBtn) {
            calcBtn.addEventListener('click', calculateVRAM);
        }

        var gpuInput = document.getElementById('gpu-memory');
        if (gpuInput) {
            gpuInput.addEventListener('keypress', function(e) {
                if (e.key === 'Enter') calculateVRAM();
            });
        }

        var quantSelect = document.getElementById('quantization');
        if (quantSelect) {
            quantSelect.addEventListener('change', calculateVRAM);
        }
    }

    document.addEventListener('DOMContentLoaded', async function() {
        AIMT.initTheme();
        init();
        
        try {
            var res = await fetch('./data/local-models.json');
            if (res.ok) {
                var data = await res.json();
                localModels = data.models || [];
                renderTable(localModels);
                calculateVRAM();
            }
        } catch (e) {
            console.error('Failed to load local models:', e);
        }
    });
})();
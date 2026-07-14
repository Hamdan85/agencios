// Typeahead model picker for the internal-admin AI config forms.
//
// Enhances every `input[data-model-picker]` (kind = text | image | video) with
// a searchable, paginated dropdown backed by /admin/openrouter_models — which
// proxies OpenRouter's public catalog per kind, so staff can only pick slugs
// OpenRouter actually serves for that use. The input stays a plain text field:
// picking a row fills it with the model id, and free typing still works (the
// value is not forced to a catalog entry).
//
// Vanilla JS on purpose — the admin has no SPA runtime; Tailwind classes below
// are compiled because tailwind-active_admin.config.js scans app/javascript.
(function () {
  'use strict';

  const DEBOUNCE_MS = 250;

  function init() {
    document.querySelectorAll('input[data-model-picker]').forEach(enhance);
  }

  function enhance(input) {
    if (input.dataset.modelPickerReady) return;
    input.dataset.modelPickerReady = '1';

    const kind = input.dataset.modelPicker;
    const url = input.dataset.pickerUrl;
    const labels = {
      loading: input.dataset.pickerLoading || '…',
      empty: input.dataset.pickerEmpty || '—',
      more: input.dataset.pickerMore || '+',
      error: input.dataset.pickerError || '!'
    };

    const wrap = document.createElement('div');
    wrap.className = 'relative';
    input.parentNode.insertBefore(wrap, input);
    wrap.appendChild(input);

    const panel = document.createElement('div');
    panel.className =
      'absolute z-50 mt-1 w-full max-h-72 overflow-y-auto rounded-md border border-gray-300 ' +
      'bg-white shadow-lg text-sm hidden dark:border-gray-700 dark:bg-gray-800';
    wrap.appendChild(panel);

    let page = 1;
    let query = '';
    let hasMore = false;
    let activeIndex = -1;
    let debounceTimer = null;
    let requestSeq = 0;

    function open() { panel.classList.remove('hidden'); }
    function close() { panel.classList.add('hidden'); activeIndex = -1; }
    function isOpen() { return !panel.classList.contains('hidden'); }

    function note(text) {
      const div = document.createElement('div');
      div.className = 'px-3 py-2 text-gray-500 dark:text-gray-400';
      div.textContent = text;
      return div;
    }

    function row(model) {
      const div = document.createElement('div');
      div.className =
        'model-picker-option px-3 py-2 cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-700';
      const name = document.createElement('div');
      name.className = 'font-medium text-gray-900 dark:text-gray-100';
      name.textContent = model.name;
      const id = document.createElement('div');
      id.className = 'font-mono text-xs text-gray-500 dark:text-gray-400';
      id.textContent = model.id;
      div.append(name, id);
      div.addEventListener('mousedown', function (e) {
        e.preventDefault(); // keep focus on the input
        pick(model.id);
      });
      return div;
    }

    function moreRow() {
      const div = document.createElement('div');
      div.className =
        'model-picker-more px-3 py-2 cursor-pointer text-center text-blue-600 ' +
        'hover:bg-gray-100 dark:text-blue-400 dark:hover:bg-gray-700';
      div.textContent = labels.more;
      div.addEventListener('mousedown', function (e) {
        e.preventDefault();
        page += 1;
        search({ append: true });
      });
      return div;
    }

    function pick(id) {
      input.value = id;
      input.dispatchEvent(new Event('input', { bubbles: true }));
      input.dispatchEvent(new Event('change', { bubbles: true }));
      close();
    }

    function render(results, append) {
      if (!append) panel.replaceChildren();
      panel.querySelector('.model-picker-more')?.remove();
      results.forEach(function (m) { panel.appendChild(row(m)); });
      if (!panel.querySelector('.model-picker-option')) panel.appendChild(note(labels.empty));
      if (hasMore) panel.appendChild(moreRow());
    }

    function search(opts) {
      const append = !!(opts && opts.append);
      if (!append) page = 1;
      const seq = ++requestSeq;
      if (!append) { panel.replaceChildren(note(labels.loading)); open(); }

      const params = new URLSearchParams({ kind: kind, q: query, page: String(page) });
      fetch(url + '?' + params, { headers: { Accept: 'application/json' } })
        .then(function (resp) {
          if (!resp.ok) throw new Error('HTTP ' + resp.status);
          return resp.json();
        })
        .then(function (data) {
          if (seq !== requestSeq) return; // a newer query superseded this one
          hasMore = !!data.has_more;
          render(data.results || [], append);
        })
        .catch(function () {
          if (seq !== requestSeq) return;
          panel.replaceChildren(note(labels.error));
        });
    }

    function options() { return Array.from(panel.querySelectorAll('.model-picker-option')); }

    function highlight(items) {
      items.forEach(function (el, i) {
        el.classList.toggle('bg-gray-100', i === activeIndex);
        el.classList.toggle('dark:bg-gray-700', i === activeIndex);
      });
      if (items[activeIndex]) items[activeIndex].scrollIntoView({ block: 'nearest' });
    }

    input.addEventListener('input', function () {
      query = input.value.trim();
      clearTimeout(debounceTimer);
      debounceTimer = setTimeout(search, DEBOUNCE_MS);
    });

    input.addEventListener('focus', function () {
      query = input.value.trim();
      search();
    });

    input.addEventListener('keydown', function (e) {
      if (!isOpen()) return;
      const items = options();
      if (e.key === 'ArrowDown') {
        e.preventDefault();
        activeIndex = Math.min(activeIndex + 1, items.length - 1);
        highlight(items);
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        activeIndex = Math.max(activeIndex - 1, 0);
        highlight(items);
      } else if (e.key === 'Enter') {
        if (activeIndex >= 0 && items[activeIndex]) {
          e.preventDefault();
          items[activeIndex].dispatchEvent(new Event('mousedown'));
        }
      } else if (e.key === 'Escape') {
        close();
      }
    });

    input.addEventListener('blur', function () {
      // Delay so a mousedown on an option lands before the panel hides.
      setTimeout(close, 150);
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();

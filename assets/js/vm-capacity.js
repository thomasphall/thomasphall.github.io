(function () {
  'use strict';

  function calculateCapacity(input) {
    const integerFields = ['nodes', 'maintenance', 'failures'];
    const resourceFields = ['cpuBudget', 'memoryBudget', 'cpuLoad', 'memoryLoad', 'cpuExtra', 'memoryExtra'];
    const fields = [...integerFields, ...resourceFields, 'growth'];
    if (fields.some(key => typeof input[key] !== 'number' || !Number.isFinite(input[key]))) {
      throw new Error('Enter a number in every field.');
    }
    if (integerFields.some(key => !Number.isInteger(input[key])) || input.nodes < 1 || input.nodes > 1000 ||
        input.maintenance < 0 || input.failures < 0 || input.maintenance > 999 || input.failures > 999) {
      throw new Error('Use whole worker counts: 1–1,000 eligible workers and 0–999 for each outage count.');
    }
    if (input.maintenance + input.failures >= input.nodes) {
      throw new Error('At least one eligible worker must remain available. Reduce outages or add workers.');
    }
    if (input.cpuBudget < 0.001 || input.memoryBudget < 0.001 || resourceFields.some(key => input[key] < 0 || input[key] > 1e9) ||
        input.growth < 0 || input.growth > 1000) {
      throw new Error('Budgets must be at least 0.001. Loads must be zero or greater, resource values at most 1 billion, and growth 0–1,000%.');
    }
    const unavailable = input.maintenance + input.failures;
    const survivors = input.nodes - unavailable;
    const cpuPlanned = input.cpuLoad * (1 + input.growth / 100) + input.cpuExtra;
    const memoryPlanned = input.memoryLoad * (1 + input.growth / 100) + input.memoryExtra;
    const cpuAvailable = survivors * input.cpuBudget;
    const memoryAvailable = survivors * input.memoryBudget;
    // Remove floating-point noise only at the scale of machine precision.
    function difference(available, planned) {
      const gap = available - planned;
      return Math.abs(gap) <= Number.EPSILON * Math.max(1, available, planned) * 8 ? 0 : gap;
    }
    function roundUp(value) {
      const nearest = Math.round(value);
      return Math.abs(value - nearest) <= Number.EPSILON * Math.max(1, value) * 8 ? nearest : Math.ceil(value);
    }
    const cpuRemaining = difference(cpuAvailable, cpuPlanned);
    const memoryRemaining = difference(memoryAvailable, memoryPlanned);
    const minimumNodes = Math.max(1, roundUp(cpuPlanned / input.cpuBudget), roundUp(memoryPlanned / input.memoryBudget)) + unavailable;
    const state = cpuRemaining < 0 || memoryRemaining < 0 ? 'shortfall' : cpuRemaining === 0 || memoryRemaining === 0 ? 'limit' : 'fits';
    return { nodes: input.nodes, unavailable, survivors, cpuPlanned, memoryPlanned, cpuAvailable, memoryAvailable,
      cpuRemaining, memoryRemaining, minimumNodes, additional: Math.max(0, minimumNodes - input.nodes), state };
  }

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { calculateCapacity };
  }
  if (typeof document === 'undefined') return;
  const form = document.getElementById('vm-capacity-form');
  if (!form) return;
  const root = document.getElementById('vm-capacity-calculator');
  const results = document.getElementById('vm-capacity-results');
  const error = document.getElementById('vm-capacity-error');
  const formatter = new Intl.NumberFormat('en-US', { maximumFractionDigits: 3 });
  function format(value) {
    if (value !== 0 && Math.abs(value) < 0.001) return value < 0 ? '−<0.001' : '<0.001';
    return formatter.format(value);
  }
  function update() {
    try {
      const input = Object.fromEntries(Array.from(form.querySelectorAll('input[name]'), field => [field.name, field.valueAsNumber]));
      const output = calculateCapacity(input);
      const statuses = { shortfall: 'Capacity shortfall', limit: 'At the budget limit', fits: 'Aggregate load fits the entered budgets' };
      for (const element of root.querySelectorAll('[data-result]')) {
        const key = element.dataset.result;
        element.textContent = key === 'status' ? statuses[output.state] : key === 'additional'
          ? output.additional > 0 ? `${format(output.additional)} more than the entered worker count.` : 'No additional workers required by this arithmetic.'
          : format(output[key]);
      }
      results.dataset.state = output.state;
      results.hidden = false;
      error.hidden = true;
    } catch (problem) {
      results.hidden = true;
      error.textContent = problem.message;
      error.hidden = false;
    }
  }
  form.hidden = false;
  form.addEventListener('submit', event => { event.preventDefault(); update(); });
  form.addEventListener('input', () => {
    results.hidden = true;
    error.hidden = true;
  });
  form.addEventListener('reset', () => { setTimeout(update, 0); });
  update();
})();

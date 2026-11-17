const assert = require('node:assert/strict');
const { calculateCapacity } = require('../assets/js/vm-capacity.js');
const example = { nodes: 6, maintenance: 1, failures: 1, growth: 20, cpuBudget: 56, memoryBudget: 448, cpuLoad: 190, memoryLoad: 1400, cpuExtra: 8, memoryExtra: 64 };
const result = calculateCapacity(example);
assert.equal(result.cpuPlanned, 236);
assert.equal(result.memoryPlanned, 1744);
assert.equal(result.cpuRemaining, -12);
assert.equal(result.memoryRemaining, 48);
assert.equal(result.minimumNodes, 7);
assert.equal(result.state, 'shortfall');
const oneOut = calculateCapacity({ ...example, failures: 0 });
assert.equal(oneOut.cpuRemaining, 44);
assert.equal(oneOut.memoryRemaining, 496);
assert.equal(oneOut.state, 'fits');
assert.equal(calculateCapacity({ ...example, nodes: 7 }).additional, 0);
assert.equal(calculateCapacity({ ...example, memoryLoad: 2000 }).minimumNodes, 8);
assert.equal(calculateCapacity({ ...example, growth: 0, cpuLoad: 216 }).state, 'limit');
assert.equal(calculateCapacity({ ...example, nodes: 1, maintenance: 0, failures: 0, growth: 0, cpuBudget: 0.3, cpuLoad: 0.1 + 0.2, cpuExtra: 0, memoryLoad: 0, memoryExtra: 0 }).minimumNodes, 1);
assert.equal(calculateCapacity({ ...example, cpuLoad: 0, memoryLoad: 0, cpuExtra: 0, memoryExtra: 0 }).minimumNodes, 3);
for (const patch of [{ nodes: 0 }, { nodes: 2 }, { nodes: 2.5 }, { cpuBudget: 0 }, { memoryBudget: -1 }, { growth: -1 }, { growth: 1001 }, { cpuLoad: NaN }, { memoryLoad: Infinity }, { maintenance: -1 }, { cpuExtra: -1 }, { nodes: 1001 }]) {
  assert.throws(() => calculateCapacity({ ...example, ...patch }));
}
console.log('Capacity example, outage scenarios, CPU and memory limits, rounding, zero demand, and invalid inputs passed.');

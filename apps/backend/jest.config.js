/** TESTING_STRATEGY.md §3: Jest, 80% de cobertura en código de dominio (modules/**). */
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  rootDir: '.',
  testRegex: '.*\\.spec\\.ts$',
  collectCoverageFrom: ['src/modules/**/*.ts', '!src/**/*.module.ts'],
  coverageThreshold: {
    'src/modules/**': { lines: 80 },
  },
};

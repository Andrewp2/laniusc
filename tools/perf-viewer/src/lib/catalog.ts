import type { PerformanceCatalog } from './types';

export function loadCatalog(): PerformanceCatalog {
  const catalog = window.LANIUS_PERFORMANCE_CATALOG;
  if (!catalog || catalog.schema !== 'lanius.performance-catalog.v1' || !Array.isArray(catalog.results)) {
    return {
      schema: 'lanius.performance-catalog.v1',
      generated_at_unix_seconds: 0,
      results: [],
      invalid_results: [{ path: 'performance-data.js', error: 'catalog is missing or malformed' }],
    };
  }
  return catalog;
}

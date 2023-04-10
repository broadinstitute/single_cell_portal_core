/**
 * Jest breaks on `import.meta.hot`, so enable mocking this in tests
 */
export default function importMetaHot() {
  return import.meta.hot
}

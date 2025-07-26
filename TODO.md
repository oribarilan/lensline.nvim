# TODO: Legacy Code, Technical Debt, and Issues

## 🚨 Critical Issues (High Priority)

### Memory and Stability Issues

- [x] **Fix timer memory leak** in [`lua/lensline/setup.lua`](lua/lensline/setup.lua)
  - ✅ Replaced per-buffer timers with single global timer using `vim.defer_fn()`
  - ✅ Simplified to refresh only current buffer (covers 99% of use cases)
  - ✅ Added proper timer cleanup in `disable()` and `VimLeavePre`
  - ✅ Reduced code complexity from ~40 lines to ~15 lines
  - Prevents memory leaks and improves performance

- [ ] **Fix circular refresh loop** in [`lua/lensline/providers/lsp/collectors/references.lua:70`](lua/lensline/providers/lsp/collectors/references.lua:70)
  - Remove direct call to `setup.refresh_current_buffer()` from collector
  - Implement event-based update mechanism instead

- [ ] **Add error handling for provider collection** in [`lua/lensline/providers/init.lua:93-165`](lua/lensline/providers/init.lua:93-165)
  - Wrap provider calls in pcall to prevent hanging
  - Ensure callback is always called even if some providers fail
  - Add timeout mechanism for slow providers

## 🔧 Technical Debt (Medium Priority)

### Architecture and Code Organization

- [ ] **Remove deprecated legacy function** in [`lua/lensline/providers/init.lua:35-40`](lua/lensline/providers/init.lua:35-40)
  - Delete `M.collect_lens_data()` function after confirming no references
  - Complete architectural transition cleanup

- [ ] **Simplify provider ordering logic** in [`lua/lensline/providers/init.lua:48-86`](lua/lensline/providers/init.lua:48-86)
  - Use explicit order array instead of complex known_provider_order logic
  - Reduce code duplication in provider iteration

- [ ] **Centralize cache management**
  - Create unified cache service to replace manual cache logic in [`lua/lensline/providers/lsp/init.lua:11-27`](lua/lensline/providers/lsp/init.lua:11-27)
  - Standardize cache TTL handling across all providers
  - Implement centralized cache invalidation strategy

### API Cleanup

- [ ] **Remove debug functions from production API** in [`lua/lensline/init.lua:44-83`](lua/lensline/init.lua:44-83)
  - Move `M.debug_lsp()` and `M.test_manual_references()` to debug module
  - Keep functions available but not exposed in main API

## ⚠️ Code Quality Issues (Low Priority)

### Code Cleanup

- [ ] **Remove unused utility function** in [`lua/lensline/utils.lua:29-37`](lua/lensline/utils.lua:29-37)
  - Delete `M.format_reference_count()` as it duplicates collector logic
  - Ensure no references exist before removal

- [ ] **Standardize error handling patterns**
  - Review error handling in [`lua/lensline/utils.lua`](lua/lensline/utils.lua)
  - Implement consistent error handling across all modules
  - Follow patterns established in [`lua/lensline/core/function_discovery.lua`](lua/lensline/core/function_discovery.lua)

## 📝 Notes

- The codebase shows evidence of active refactoring with architectural transition comments
- Most issues are related to stability and maintainability rather than functionality
- Consider addressing critical issues before adding new features
- Some debt items may become obsolete as the architectural transition completes
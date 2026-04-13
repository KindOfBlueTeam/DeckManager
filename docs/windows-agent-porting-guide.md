# DeckRipperHS Windows Agent — Porting Guide

**Status:** Not yet started  
**Target platform:** Windows 10/11 x64  
**Reference machine:** AMD Ryzen 9 7950X, 96 GB DDR5, RTX 4060 Ti 16 GB, 4 TB NVMe

---

## 1. What Transfers from macOS

### Concepts that are identical
- **Mono runtime structure hierarchy:** MonoDomain → MonoAssembly → MonoImage → MonoClass → instances. The data model is the same.
- **Hearthstone's C# class names:** `NetCacheCollection`, `CardStack`, `CardDefinition`, `CollectionDeck`, etc. These are game code, not platform-specific.
- **Card ID format:** String IDs like `"EX1_055"` and `"CS2_032"` are game-level identifiers, identical across platforms.
- **The scanning approach:** Bottom-up string scanning → pointer resolution → field offset discovery → heap pattern matching. This methodology works regardless of OS.
- **Diagnostic tooling strategy:** Iterative probing with progressive refinement. The phase 1-9 diagnostic approach should be replicated.
- **Snapshot-based offline analysis:** Dump memory to file, analyze at disk speed.

### Things that WILL differ
- **Mono struct offsets:** Field positions within MonoClass, MonoImage, etc. will differ between the macOS and Windows Unity builds. Different compilers (Clang vs MSVC), different alignment rules, possibly different Mono versions.
- **Instance field offsets:** `NetCacheCollection.Stacks` may not be at +0x10 on Windows. Must be rediscovered.
- **VTable layout:** The vtable/class pointer relationship will differ.
- **Memory region characteristics:** Heap addresses, region sizes, protection flags will all be different.
- **Parent class layout:** The "shifted" parent layout (name at +0x40 instead of +0x28) may not apply on Windows.

---

## 2. Windows Memory APIs

### Equivalent of macOS Mach APIs

| macOS | Windows | Notes |
|-------|---------|-------|
| `task_for_pid()` | `OpenProcess(PROCESS_VM_READ, ...)` | Needs `SeDebugPrivilege` or admin |
| `mach_vm_read()` | `ReadProcessMemory()` | Direct equivalent |
| `mach_vm_region()` | `VirtualQueryEx()` | Returns `MEMORY_BASIC_INFORMATION` |
| No equivalent | `EnumProcessModules()` | Find loaded DLLs by name |

### Key differences
- **No task ports:** Windows uses process handles from `OpenProcess()`
- **Permissions:** Need admin rights or `SeDebugPrivilege` to read another process
- **Module enumeration:** `EnumProcessModules` + `GetModuleFileNameEx` can find `mono-2.0-bdwgc.dll` directly, which gives us the Mono runtime base address — potentially simpler than our macOS approach
- **Memory regions:** `VirtualQueryEx` returns `MEM_COMMIT` / `MEM_RESERVE` / `MEM_FREE` states and `PAGE_*` protection flags

### Recommended language: **Rust** or **C++**
- Rust: `winapi` or `windows` crate for Win32 APIs, excellent performance, safe memory handling
- C++: Direct Win32 API access, simpler FFI if needed
- C#: Would also work and has nice process memory libraries, but adds .NET dependency

---

## 3. Suggested Implementation Order

### Phase A: Memory reader foundation
1. `OpenProcess` with `PROCESS_VM_READ | PROCESS_QUERY_INFORMATION`
2. `VirtualQueryEx` loop to enumerate committed readable regions
3. `ReadProcessMemory` wrapper with error handling
4. Snapshot dumper (same binary format as macOS — cross-platform analysis possible)

### Phase B: Find Mono runtime
1. Use `EnumProcessModules` to find `mono-2.0-bdwgc.dll` base address
2. Alternatively, scan for `"Assembly-CSharp"` string (same approach as macOS)
3. Find root domain — may be exported as `mono_get_root_domain` symbol in the DLL
4. Walk assembly list to find Assembly-CSharp image

### Phase C: Offset discovery
1. Dump MonoImage structure (same approach as macOS Phase 1)
2. Scan for `"NetCacheCollection"` string, find MonoClass
3. Determine MonoClass layout: where is name, namespace, image, parent?
4. Read field descriptors to get instance offsets for Stacks, TotalCardsOwned
5. Pattern-match heap for live instances
6. Read CardStack → CardDefinition → card ID strings

### Phase D: Collection extraction
1. Implement the proven extraction flow using discovered offsets
2. Output same JSON format as macOS agent
3. POST to same web service endpoint

### Phase E: Deck reading (if macOS deck reading is working by then)
1. Apply same deck class offset discovery
2. Extract deck names, hero classes, card lists

---

## 4. Snapshot File Format (Cross-Platform)

Both macOS and Windows agents should produce the same snapshot format:

```
Header:
  [8 bytes] Magic: 0x48534D454D444D50 ("HSMEMDUP")
  [4 bytes] Version: 1
  [4 bytes] Region count (uint32)

Per region:
  [8 bytes] Virtual address (uint64)
  [8 bytes] Region size (uint64)
  [8 bytes] Flags (uint64) — 1 = writable, 0 = read-only
  [N bytes] Region data

Companion .index file: text, one line per region:
  0x{address} {size} {rwx_flags}
```

This means a Windows snapshot can be analyzed on macOS and vice versa — useful for development, though the Mono offsets will differ.

---

## 5. Known macOS Offsets (DO NOT USE ON WINDOWS — Rediscover)

These are documented here as a reference for what to look for, not as values to reuse.

### MonoClass (macOS, April 2026)
| Field | macOS Offset | Windows: TBD |
|-------|-------------|--------------|
| Parent class | +0x18 | ? |
| Image pointer | +0x20 | ? |
| Class name | +0x28 | ? |
| Namespace | +0x30 | ? |
| Field descriptors | +0xF0+ | ? |

### NetCacheCollection Instance (macOS)
| Field | macOS Offset | Windows: TBD |
|-------|-------------|--------------|
| Stacks (List) | +0x10 | ? |
| CoreCardsUnlockedPerClass | +0x18 | ? |
| TotalCardsOwned | +0x20 | ? |

### CardStack (macOS)
| Field | macOS Offset | Windows: TBD |
|-------|-------------|--------------|
| CardDefinition | +0x10 | ? |
| Count | +0x20 | ? |
| NumSeen | +0x24 | ? |

### CardDefinition (macOS)
| Field | macOS Offset | Windows: TBD |
|-------|-------------|--------------|
| Card ID (MonoString) | +0x10 | ? |
| Premium flag | +0x14 | ? |

---

## 6. Windows-Specific Advantages

- **96 GB RAM:** Entire snapshot fits in memory trivially. No need for mmap tricks.
- **`mono_get_root_domain` export:** The Mono DLL on Windows may export this symbol, letting us skip the expensive root domain scan entirely.
- **Module base address:** `EnumProcessModules` gives us the exact address of `mono-2.0-bdwgc.dll`, which we can use to find exported functions and global pointers.
- **Faster iteration:** With 16 cores and 96 GB, diagnostics that take 15 minutes on macOS should take seconds on Windows.

---

## 7. Testing Strategy

1. Install Hearthstone on Windows via Battle.net
2. Run the agent, take a snapshot
3. Run offset discovery diagnostics
4. Compare class names and field names to macOS (should be identical)
5. Document Windows-specific offsets in `mono-offset-map.md` alongside macOS offsets
6. Verify extracted card IDs match between platforms

//
//  SharedStateTests.swift
//  Storyboard3DWorkspaceTests
//

import Testing

/// Groups the suites that change app-wide state: where projects are stored
/// (`ProjectStore.storageOverride`) and preferences kept in `UserDefaults`. Serialized, so
/// those suites run one after another instead of changing that state under each other.
/// Suites that don't touch it still run in parallel.
@Suite(.serialized)
struct SharedStateTests {}

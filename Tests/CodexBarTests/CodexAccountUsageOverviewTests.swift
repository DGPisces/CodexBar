import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

private actor OverviewFetchRecorder {
    var workspaceIDs: [String] = []

    func record(_ id: String) {
        self.workspaceIDs.append(id)
    }
}

@MainActor
extension CodexAccountScopedRefreshTests {
    @Test
    func `overview retains every inventory row and never borrows selected account data`() async throws {
        try await self.withSelectedAccountRetentionFixture(sameEmail: true, count: 8) { store, _, accounts in
            store.codexAccountSnapshots.removeAll { $0.id == accounts[7].id }
            let source = store.settings.codexActiveSource
            let overview = try #require(store.codexAccountUsageOverview(onRefresh: { _ in }))
            #expect(overview.rows.count == 8)
            #expect(overview.rows.filter(\.isFollowed).map(\.id) == [accounts[0].id])
            #expect(overview.rows.filter(\.isSystem).isEmpty)
            let unavailable = try #require(overview.rows.first { $0.id == accounts[7].id })
            #expect(unavailable.model.metrics.isEmpty)
            #expect(unavailable.model.planText == nil)
            #expect(unavailable.model.creditsText == nil)
            #expect(unavailable.updatedAt == nil)
            #expect(overview.rows.allSatisfy { $0.model.tokenUsage == nil })
            #expect(overview.rows.first { $0.id == accounts[1].id }?.error != nil)
            #expect(store.settings.codexActiveSource == source)
        }
    }

    @Test
    func `overview privacy labels stay distinct across same email workspaces`() async throws {
        try await self.withSelectedAccountRetentionFixture(sameEmail: true) { store, _, _ in
            store.settings.hidePersonalInfo = true
            let overview = try #require(store.codexAccountUsageOverview(onRefresh: { _ in }))
            #expect(Set(overview.rows.map(\.title)).count == 2)
            #expect(overview.rows.allSatisfy { !$0.title.contains("@") && !$0.model.email.contains("@") })
        }
    }

    @Test
    func `settings refreshes one sibling without changing followed usage or credentials`() async throws {
        try await self.withSelectedAccountRetentionFixture(sameEmail: true) { store, snapshotStore, accounts in
            let selected = try #require(store.codexAccountSnapshots.first { $0.id == accounts[0].id }?.snapshot)
            store.snapshots[.codex] = selected
            let source = store.settings.codexActiveSource
            let systemAuthURL = try URL(fileURLWithPath: #require(store.environmentBase["CODEX_HOME"]))
                .appendingPathComponent("auth.json")
            let systemAuthBefore = try? Data(contentsOf: systemAuthURL)
            let metadata = try FileManagedCodexAccountStore(
                fileURL: #require(store.settings._test_managedCodexAccountStoreURL)).loadAccountMetadata()
            let authFiles = try metadata.accounts.map {
                try Data(contentsOf: URL(fileURLWithPath: $0.managedHomePath).appendingPathComponent("auth.json"))
            }
            let recorder = OverviewFetchRecorder()
            self.installOverviewProvider(on: store, accounts: accounts, recorder: recorder)

            await store.refreshCodexAccountsForSettings([accounts[1].id])
            await store.widgetSnapshotPersistTask?.value

            #expect(await recorder.workspaceIDs == accounts[1...1].compactMap(\.workspaceAccountID))
            #expect(store.settings.codexActiveSource == source)
            #expect(store.snapshots[.codex]?.updatedAt == selected.updatedAt)
            #expect(store.snapshots[.codex]?.primary == selected.primary)
            #expect(store.codexAccountSnapshots.count == 2)
            #expect(snapshotStore.load(for: accounts).first { $0.id == accounts[1].id }?.snapshot?.primary?
                .usedPercent == 77)
            #expect(store.codexSettingsRefreshingAccountIDs.isEmpty)
            #expect((try? Data(contentsOf: systemAuthURL)) == systemAuthBefore)
            for (index, account) in metadata.accounts.enumerated() {
                #expect(try Data(contentsOf: URL(fileURLWithPath: account.managedHomePath)
                        .appendingPathComponent("auth.json")) == authFiles[index])
            }
        }
    }

    @Test
    func `refresh all batches every account beyond the menu limit`() async throws {
        try await self
            .withSelectedAccountRetentionFixture(sameEmail: true, count: 8) { store, snapshotStore, accounts in
                let source = store.settings.codexActiveSource
                let recorder = OverviewFetchRecorder()
                self.installOverviewProvider(on: store, accounts: accounts, recorder: recorder)

                await store.refreshCodexAccountsForSettings(Set(accounts.map(\.id)))
                await store.widgetSnapshotPersistTask?.value

                let fetched = await recorder.workspaceIDs
                #expect(fetched.count == 8)
                #expect(Set(fetched) == Set(accounts.compactMap(\.workspaceAccountID)))
                #expect(store.codexAccountSnapshots.count == 8)
                #expect(snapshotStore.load(for: accounts).allSatisfy { $0.snapshot?.primary?.usedPercent == 77 })
                #expect(store.settings.codexActiveSource == source)
            }
    }

    @Test
    func `failed sibling refresh preserves its age and leaves followed errors alone`() async throws {
        try await self.withSelectedAccountRetentionFixture(sameEmail: false) { store, _, accounts in
            let previous = try #require(store.codexAccountSnapshots.first { $0.id == accounts[1].id })
            self.installContextualCodexProvider(on: store, sourceLabel: "oauth", kind: .oauth) { _ in
                throw URLError(.notConnectedToInternet)
            }
            await store.refreshCodexAccountsForSettings([accounts[1].id])
            await store.widgetSnapshotPersistTask?.value
            let refreshed = try #require(store.codexAccountSnapshots.first { $0.id == accounts[1].id })
            #expect(refreshed.snapshot?.updatedAt == previous.snapshot?.updatedAt)
            #expect(refreshed.error != nil)
            #expect(store.errors[.codex] == nil)
            #expect(store.codexAccountSnapshots.count == 2)
        }
    }

    private func installOverviewProvider(
        on store: UsageStore,
        accounts: [CodexVisibleAccount],
        recorder: OverviewFetchRecorder)
    {
        self.installContextualCodexProvider(on: store, sourceLabel: "oauth", kind: .oauth) { context in
            let workspace = try #require(context.codexWorkspaceID)
            await recorder.record(workspace)
            let account = try #require(accounts.first { $0.workspaceAccountID == workspace })
            return UsageSnapshot(
                primary: RateWindow(usedPercent: 77, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: Date(),
                identity: ProviderIdentitySnapshot(
                    providerID: .codex,
                    accountEmail: account.email,
                    accountOrganization: nil,
                    loginMethod: "Pro",
                    accountID: workspace))
        }
    }

    @Test
    func `settings rejects a suspended result after followed account changes`() async throws {
        try await self.withSelectedAccountRetentionFixture(sameEmail: true) { store, _, accounts in
            let previous = try #require(store.codexAccountSnapshots.first { $0.id == accounts[1].id })
            let settings = store.settings
            let newSource = accounts[1].selectionSource
            self.installContextualCodexProvider(on: store, sourceLabel: "oauth", kind: .oauth) { context in
                await MainActor.run { settings.codexActiveSource = newSource }
                return UsageSnapshot(
                    primary: RateWindow(usedPercent: 99, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                    secondary: nil,
                    updatedAt: Date(),
                    identity: ProviderIdentitySnapshot(
                        providerID: .codex,
                        accountEmail: accounts[1].email,
                        accountOrganization: nil,
                        loginMethod: "Pro",
                        accountID: context.codexWorkspaceID))
            }
            await store.refreshCodexAccountsForSettings([accounts[1].id])
            await store.widgetSnapshotPersistTask?.value
            #expect(store.codexAccountSnapshots.first { $0.id == accounts[1].id }?.snapshot?.updatedAt
                == previous.snapshot?.updatedAt)
            #expect(store.codexSettingsRefreshingAccountIDs.isEmpty)
        }
    }

    @Test
    func `ambient PAT mode does not attribute one token to visible accounts`() async throws {
        try await self.withSelectedAccountRetentionFixture(sameEmail: false) { store, _, accounts in
            store.settings.codexUsageDataSource = .pat
            let recorder = OverviewFetchRecorder()
            self.installOverviewProvider(on: store, accounts: accounts, recorder: recorder)
            #expect(store.codexAccountUsageOverview(onRefresh: { _ in }) == nil)
            await store.refreshCodexAccountsForSettings(Set(accounts.map(\.id)))
            #expect(await recorder.workspaceIDs.isEmpty)
        }
    }

    @Test
    func `followed errors appear only under their verified account owner`() async throws {
        try await self.withSelectedAccountRetentionFixture(sameEmail: true) { store, _, accounts in
            store.errors[.codex] = "Selected account failed"
            store.lastCodexUsagePublicationGuard = UsageStore.codexScopedRefreshGuard(for: accounts[0])
            var overview = try #require(store.codexAccountUsageOverview(onRefresh: { _ in }))
            #expect(overview.rows.first { $0.id == accounts[0].id }?.error == "Selected account failed")
            #expect(overview.rows.first { $0.id == accounts[1].id }?.error == "Network error")

            store.lastCodexUsagePublicationGuard = UsageStore.codexScopedRefreshGuard(for: accounts[1])
            overview = try #require(store.codexAccountUsageOverview(onRefresh: { _ in }))
            #expect(overview.rows.first { $0.id == accounts[0].id }?.error == nil)
        }
    }

    @Test
    func `settings header refresh batches siblings and preserves dashboard enrichment for followed account`() async throws {
        try await self.withSelectedAccountRetentionFixture(sameEmail: true) { store, _, accounts in
            store.settings.openAIWebAccessEnabled = true
            store.settings.codexCookieSource = .auto
            let recorder = OverviewFetchRecorder()
            self.installOverviewProvider(on: store, accounts: accounts, recorder: recorder)

            var dashboardCalled = false
            store._test_openAIDashboardLoaderOverride = { accountEmail, _, _, _ in
                dashboardCalled = true
                return self.dashboard(email: accounts[0].email, creditsRemaining: 42, usedPercent: 10)
            }
            defer { store._test_openAIDashboardLoaderOverride = nil }

            await store.refreshCodexFromSettingsHeader(allowDisabled: true)
            let fetched = await recorder.workspaceIDs
            #expect(Set(fetched) == Set(accounts.compactMap(\.workspaceAccountID)))
            #expect(dashboardCalled)
        }
    }
}

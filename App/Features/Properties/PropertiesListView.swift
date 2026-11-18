import SwiftUI

struct BottomBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 8) {
            Hairline()
            content
                .padding(.horizontal, TPSpacing.gutter)
                .padding(.top, 12)
                .padding(.bottom, 8)
        }
        .background(TPColor.paper)
    }
}

struct PropertiesListView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        _ = model.revision
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if model.properties.isEmpty {
                        emptyState
                    } else {
                        propertyList
                    }
                }
                .padding(.horizontal, TPSpacing.gutter)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            BottomBar {
                Button {
                    router.present(sheet: .addProperty)
                } label: {
                    Label("Start inspection", systemImage: "plus")
                }
                .buttonStyle(TPPrimaryButtonStyle())
                .accessibilityIdentifier("inspection.start")
            }
        }
        .background(TPColor.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Turnproof")
            Text("Properties")
                .font(TPType.display())
                .foregroundStyle(TPColor.ink)
            Text("Condition reports that hold up.")
                .font(TPType.body())
                .foregroundStyle(TPColor.inkSecondary)
            Hairline().padding(.top, 12)
            // Stacks at accessibility sizes instead of truncating the counts.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                Text("\(model.properties.count) units").font(TPType.eyebrow())
                if !dynamicTypeSize.isAccessibilitySize { Text("·").foregroundStyle(TPColor.inkTertiary) }
                Text("\(sealedCount) sealed reports").font(TPType.eyebrow())
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            }
            .foregroundStyle(TPColor.inkSecondary)
            .padding(.vertical, 12)
        }
    }

    private var sealedCount: Int {
        model.properties.reduce(0) { total, property in
            total + model.inspections(for: property).reduce(0) { $0 + model.reports(for: $1).count }
        }
    }

    private var propertyList: some View {
        VStack(spacing: 16) {
            ForEach(model.properties) { property in
                Button {
                    router.push(.property(property.id))
                } label: {
                    PropertyRow(property: property,
                                active: model.inspections(for: property).first(where: { $0.status == .draft }),
                                sealed: model.inspections(for: property).compactMap { inspection in
                                    model.reports(for: inspection).first
                                }.first)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("property.row.\(property.id.uuidString)")
            }
            Button {
                router.present(sheet: .addProperty)
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(.title3, weight: .medium))
                    Text("Add your first unit").font(TPType.bodyStrong())
                    Text("Register an address and start a baseline.")
                        .font(TPType.small()).foregroundStyle(TPColor.inkSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .overlay(
                    Rectangle().stroke(TPColor.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                )
                .foregroundStyle(TPColor.ink)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("property.add")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No units yet.")
                .font(TPType.heading())
                .foregroundStyle(TPColor.ink)
            Text("Add a unit, walk it room by room, and hand the tenant a signed condition report before they move in or out.")
                .font(TPType.body())
                .foregroundStyle(TPColor.inkSecondary)
        }
        .padding(.vertical, 32)
    }
}

struct PropertyRow: View {
    let property: Property
    let active: Inspection?
    let sealed: SealedReport?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(property.label)
                    .font(TPType.heading())
                    .foregroundStyle(TPColor.ink)
                Spacer()
                if sealed != nil {
                    StatusChip(text: "Sealed", color: TPColor.good, background: TPColor.goodSoft)
                } else if active != nil {
                    StatusChip(text: "In progress", color: TPColor.warning, background: TPColor.warningSoft)
                }
            }
            Text([property.addressLine, property.unit].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(TPType.small())
                .foregroundStyle(TPColor.inkSecondary)
            Hairline()
            HStack {
                Text(active.map { "\($0.kind.title) inspection · \($0.status.rawValue)" }
                     ?? sealed.map { "Report sealed \(Self.date($0.generatedAt))" }
                     ?? "No reports yet")
                    .font(TPType.small())
                    .foregroundStyle(TPColor.inkSecondary)
                Spacer()
                if let sealed {
                    Text(sealed.sha256.uppercased().prefix(4))
                        .font(TPType.mono())
                        .foregroundStyle(TPColor.inkTertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(TPColor.inkTertiary)
            }
        }
        .padding(16)
        .background(TPColor.paperRaised)
        .overlay(Rectangle().stroke(TPColor.hairline, lineWidth: 1))
    }

    static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }
}

struct AddPropertySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var address = ""
    @State private var unit = ""
    @State private var landlord = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Eyebrow(text: "New unit")
                    Text("Where is it?")
                        .font(TPType.title())
                        .foregroundStyle(TPColor.ink)
                    field("Label", text: $label, id: "property.field.label")
                    field("Address", text: $address, id: "property.field.address")
                    field("Unit (optional)", text: $unit, id: "property.field.unit")
                    field("Your name", text: $landlord, id: "property.field.landlord")
                    if let error {
                        Text(error).font(TPType.small()).foregroundStyle(TPColor.damage)
                    }
                }
                .padding(TPSpacing.gutter)
            }
            .background(TPColor.paper.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                BottomBar {
                    Button("Save unit") {
                        do {
                            try model.addProperty(label: label, address: address, unit: unit, landlord: landlord)
                            dismiss()
                        } catch RepositoryError.invalidLabel {
                            error = "A label is required."
                        } catch RepositoryError.invalidAddress {
                            error = "An address is required."
                        } catch {
                            self.error = "Could not save this unit."
                        }
                    }
                    .buttonStyle(TPPrimaryButtonStyle())
                    .accessibilityIdentifier("property.save")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: title)
            TextField("", text: text)
                .font(TPType.body())
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(TPColor.paperRaised)
                .overlay(Rectangle().stroke(TPColor.hairline, lineWidth: 1))
                .accessibilityIdentifier(id)
        }
    }
}

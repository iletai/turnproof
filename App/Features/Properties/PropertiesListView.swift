import SwiftUI

/// "Maple Court · Unit 2B"; file-private so parallel lanes can format the same fields their own way.
private func propertyTitle(_ property: Property) -> String {
    [property.label, property.unit].filter { !$0.isEmpty }.joined(separator: " · ")
}

struct PropertiesListView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    var body: some View {
        _ = model.revision
        return Group {
            if model.properties.isEmpty {
                emptyState
            } else {
                propertyList
            }
        }
        .background(TPColor.background.ignoresSafeArea())
        .navigationTitle("Properties")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.present(sheet: .settings)
                } label: {
                    Image(systemName: "gearshape")
                }
                .foregroundStyle(TPColor.textPrimary)
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("settings.open")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.present(sheet: .addProperty)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Property")
                .accessibilityIdentifier("inspection.start")
            }
        }
    }

    private var propertyList: some View {
        List {
            if let resume = resumeInspection {
                Section("Continue") {
                    Button {
                        router.push(.rooms(resume.inspection.id))
                    } label: {
                        ResumeRow(property: resume.property,
                                  inspection: resume.inspection,
                                  done: doneRooms(resume.inspection),
                                  total: model.rooms(for: resume.inspection).count)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("inspection.resume")
                }
            }

            Section("All properties") {
                ForEach(model.properties) { property in
                    Button {
                        router.push(.property(property.id))
                    } label: {
                        PropertyRow(property: property,
                                    active: activeInspection(for: property),
                                    sealed: sealedReport(for: property))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("property.row.\(property.id.uuidString)")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No properties yet", systemImage: "building.2")
        } description: {
            Text("Add a rental unit to start its first condition report.")
        } actions: {
            Button("Add Property") {
                router.present(sheet: .addProperty)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("property.add")
        }
    }

    /// Most recently started draft across every property; drives the "Continue" section.
    private var resumeInspection: (property: Property, inspection: Inspection)? {
        let drafts = model.properties.flatMap { property in
            model.inspections(for: property)
                .filter { $0.status == .draft }
                .map { (property: property, inspection: $0) }
        }
        return drafts.max { $0.inspection.startedAt < $1.inspection.startedAt }
    }

    private func activeInspection(for property: Property) -> Inspection? {
        model.inspections(for: property).first { $0.status == .draft }
    }

    private func sealedReport(for property: Property) -> SealedReport? {
        model.inspections(for: property).compactMap { model.reports(for: $0).first }.first
    }

    private func doneRooms(_ inspection: Inspection) -> Int {
        model.rooms(for: inspection).filter { !model.findings(room: $0).isEmpty }.count
    }
}

struct PropertyRow: View {
    let property: Property
    let active: Inspection?
    let sealed: SealedReport?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(propertyTitle(property))
                    .font(.headline)
                    .foregroundStyle(TPColor.textPrimary)
                Text(property.addressLine)
                    .font(.subheadline)
                    .foregroundStyle(TPColor.textSecondary)
                statusLine
                    .padding(.top, 2)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var statusLine: some View {
        if let sealed {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(TPColor.good)
                Text("Sealed \(Self.date(sealed.generatedAt))")
                    .foregroundStyle(TPColor.textSecondary)
            }
            .font(.footnote)
        } else if active != nil {
            HStack(spacing: 6) {
                Image(systemName: "circle.dotted")
                    .foregroundStyle(TPColor.fair)
                Text("In progress")
                    .foregroundStyle(TPColor.textSecondary)
            }
            .font(.footnote)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .foregroundStyle(TPColor.textSecondary)
                Text("No reports yet")
                    .foregroundStyle(TPColor.textSecondary)
            }
            .font(.footnote)
        }
    }

    static func date(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .omitted) }
}

private struct ResumeRow: View {
    let property: Property
    let inspection: Inspection
    let done: Int
    let total: Int

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Continue inspection")
                    .font(.headline)
                    .foregroundStyle(TPColor.textPrimary)
                Text("\(propertyTitle(property)) · \(done) of \(total) rooms")
                    .font(.subheadline)
                    .foregroundStyle(TPColor.textSecondary)
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .progressViewStyle(.linear)
                    .tint(TPColor.tint)
                    .padding(.top, 2)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

struct AddPropertySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var address = ""
    @State private var unit = ""
    @State private var landlord = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Label", text: $label)
                        .accessibilityIdentifier("property.field.label")
                    TextField("Address", text: $address)
                        .accessibilityIdentifier("property.field.address")
                    TextField("Unit (optional)", text: $unit)
                        .accessibilityIdentifier("property.field.unit")
                    TextField("Your name", text: $landlord)
                        .accessibilityIdentifier("property.field.landlord")
                }
                if let error {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(TPColor.damage)
                    }
                }
            }
            .navigationTitle("New unit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save unit") { save() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("property.save")
                }
            }
        }
    }

    private func save() {
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
}

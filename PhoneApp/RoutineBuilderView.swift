import SwiftUI

struct RoutineBuilderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var drafts: [RoutineExerciseDraft]
    @FocusState private var isWeightFieldFocused: Bool
    let onSave: (WorkoutRoutine) -> Void

    init(
        initialPlans: [ExercisePlan],
        initialName: String? = nil,
        onSave: @escaping (WorkoutRoutine) -> Void
    ) {
        let plans = initialPlans.isEmpty ? [.sample] : initialPlans
        _name = State(initialValue: initialName ?? (plans.count > 1 ? "My Routine" : "Workout"))
        _drafts = State(initialValue: plans.map(RoutineExerciseDraft.init))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ROUTINE NAME")
                            .font(.caption2.bold())
                            .tracking(1.4)
                            .foregroundStyle(VibratoPalette.muted)
                        TextField("Routine name", text: $name)
                            .font(.title3.bold())
                            .padding(14)
                            .background(VibratoPalette.sand, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(18)
                    .vibratoSurface(cornerRadius: 20)

                    HStack {
                        Text("EXERCISES")
                            .font(.caption.bold())
                            .tracking(1.4)
                            .foregroundStyle(VibratoPalette.muted)
                        Spacer()
                        Text("\(drafts.count) in routine")
                            .font(.caption)
                            .foregroundStyle(VibratoPalette.muted)
                    }

                    ForEach(Array(drafts.enumerated()), id: \.element.id) { index, _ in
                        exerciseCard(at: index)
                    }

                    Button {
                        drafts.append(RoutineExerciseDraft(exercise: nextExerciseKind))
                    } label: {
                        Label("Add Exercise", systemImage: "plus")
                            .font(.headline)
                            .foregroundStyle(VibratoPalette.graphite)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(VibratoPalette.sand, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(drafts.count >= 10)

                    if !isValid {
                        Label("Every exercise needs a weight greater than 0 lb.", systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(VibratoPalette.error)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            .background(VibratoPalette.canvas.ignoresSafeArea())
            .navigationTitle("Build Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(VibratoPalette.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isWeightFieldFocused = false }
                }
            }
        }
        .tint(VibratoPalette.graphite)
        .presentationBackground(VibratoPalette.canvas)
    }

    private func exerciseCard(at index: Int) -> some View {
        VStack(spacing: 14) {
            HStack {
                Text("\(index + 1)")
                    .font(.caption.bold())
                    .foregroundStyle(VibratoPalette.graphite)
                    .frame(width: 30, height: 30)
                    .background(VibratoPalette.sand, in: Circle())
                Menu {
                    Picker("Exercise", selection: $drafts[index].exercise) {
                        ForEach(ExerciseKind.armExercises) { exercise in
                            Text(exercise.displayName).tag(exercise)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(drafts[index].exercise.displayName)
                            .font(.headline)
                        Image(systemName: "chevron.down")
                            .font(.caption.bold())
                            .foregroundStyle(VibratoPalette.muted)
                    }
                }
                Spacer()
                Button(role: .destructive) { drafts.remove(at: index) } label: {
                    Image(systemName: "trash")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(drafts[index].exercise.displayName)")
            }

            RoutineExerciseEditor(
                draft: $drafts[index],
                isWeightFieldFocused: $isWeightFieldFocused
            )

            Divider().overlay(VibratoPalette.line)

            HStack(spacing: 10) {
                orderButton("arrow.up", title: "Earlier", disabled: index == 0) {
                    drafts.swapAt(index, index - 1)
                }
                orderButton("arrow.down", title: "Later", disabled: index == drafts.count - 1) {
                    drafts.swapAt(index, index + 1)
                }
            }
        }
        .foregroundStyle(VibratoPalette.graphite)
        .padding(18)
        .vibratoSurface(cornerRadius: 20)
    }

    private func orderButton(
        _ image: String,
        title: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: image)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(VibratoPalette.sand, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .accessibilityLabel("Move \(title.lowercased())")
    }

    private var nextExerciseKind: ExerciseKind {
        ExerciseKind.armExercises.first { candidate in
            !drafts.contains(where: { $0.exercise == candidate })
        } ?? .bicepCurl
    }

    private var isValid: Bool {
        !drafts.isEmpty && drafts.allSatisfy { $0.weightPounds.isFinite && $0.weightPounds > 0 }
    }

    private func save() {
        guard isValid else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let routine = WorkoutRoutine(
            name: trimmedName.isEmpty ? "My Routine" : trimmedName,
            exercises: drafts.map(\.plan)
        )
        onSave(routine)
        dismiss()
    }
}

private struct RoutineExerciseDraft: Identifiable {
    let id: UUID
    var exercise: ExerciseKind
    var targetSets: Int
    var targetReps: Int
    var weightPounds: Double
    var restDurationSeconds: Int

    init(
        id: UUID = UUID(),
        exercise: ExerciseKind = .bicepCurl,
        targetSets: Int = 3,
        targetReps: Int = 10,
        weightPounds: Double = 20,
        restDurationSeconds: Int = 60
    ) {
        self.id = id
        self.exercise = exercise
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.weightPounds = weightPounds
        self.restDurationSeconds = restDurationSeconds
    }

    init(plan: ExercisePlan) {
        id = plan.id
        exercise = plan.exercise
        targetSets = plan.targetSets
        targetReps = plan.targetReps
        weightPounds = plan.weightPounds
        restDurationSeconds = plan.restDurationSeconds
    }

    var plan: ExercisePlan {
        ExercisePlan(
            id: id,
            exercise: exercise,
            targetSets: targetSets,
            targetReps: targetReps,
            weightKilograms: WeightConversion.kilograms(fromPounds: weightPounds),
            restDurationSeconds: restDurationSeconds
        )
    }
}

private struct RoutineExerciseEditor: View {
    @Binding var draft: RoutineExerciseDraft
    var isWeightFieldFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                compactCounter("Sets", value: $draft.targetSets, range: 1...10)
                Divider().overlay(VibratoPalette.line).frame(height: 78)
                compactCounter("Reps", value: $draft.targetReps, range: 1...50)
            }

            Divider().overlay(VibratoPalette.line)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Weight").font(.subheadline.weight(.semibold))
                    Text("Used for every set")
                        .font(.caption2).foregroundStyle(VibratoPalette.muted)
                }
                Spacer()
                TextField("0", value: $draft.weightPounds, format: .number.precision(.fractionLength(1)))
                    .keyboardType(.decimalPad)
                    .focused(isWeightFieldFocused)
                    .multilineTextAlignment(.trailing)
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .padding(.horizontal, 10)
                    .frame(height: 40)
                    .frame(width: 90)
                    .background(VibratoPalette.sand, in: RoundedRectangle(cornerRadius: 10))
                Text("lb").foregroundStyle(VibratoPalette.muted)
            }

            Divider().overlay(VibratoPalette.line)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Rest after each set").font(.subheadline.weight(.semibold))
                    Text("After the last set, this is the rest before the next exercise.")
                        .font(.caption2).foregroundStyle(VibratoPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Picker("Rest after each set", selection: $draft.restDurationSeconds) {
                    ForEach([0, 15, 30, 45, 60, 90, 120, 180], id: \.self) { seconds in
                        Text(ExercisePlan.formattedRestDuration(seconds: seconds)).tag(seconds)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    private func compactCounter(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        VStack(spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.bold())
                .tracking(1.2)
                .foregroundStyle(VibratoPalette.muted)
            HStack(spacing: 8) {
                Button {
                    guard value.wrappedValue > range.lowerBound else { return }
                    value.wrappedValue -= 1
                } label: {
                    Image(systemName: "minus")
                        .font(.caption.bold())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .background(VibratoPalette.sand, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(RoutineCounterButtonStyle())
                .disabled(value.wrappedValue <= range.lowerBound)
                .opacity(value.wrappedValue <= range.lowerBound ? 0.35 : 1)
                .accessibilityLabel("Decrease \(title.lowercased())")

                Text("\(value.wrappedValue)")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .frame(width: 30)

                Button {
                    guard value.wrappedValue < range.upperBound else { return }
                    value.wrappedValue += 1
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.bold())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .background(VibratoPalette.sand, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(RoutineCounterButtonStyle())
                .disabled(value.wrappedValue >= range.upperBound)
                .opacity(value.wrappedValue >= range.upperBound ? 0.35 : 1)
                .accessibilityLabel("Increase \(title.lowercased())")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RoutineCounterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

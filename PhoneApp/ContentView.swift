import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var connectivity: PhoneConnectivityManager
    @EnvironmentObject private var history: WorkoutHistoryStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var exercise: ExerciseKind = .bicepCurl
    @State private var targetSets = 3
    @State private var targetReps = 10
    @State private var weightPounds: Double? = 22.0
    @State private var restDurationSeconds = 60
    @State private var savedEventTimestamp: Date?
    @State private var feedbackPrompt: WorkoutFeedbackPrompt?
    @State private var skippedFeedbackWorkoutIDs: Set<UUID> = []
    @State private var isWorkoutOptionsExpanded = false
    @State private var activeRoutine: WorkoutRoutine?
    @State private var isRoutineBuilderPresented = false
    @State private var selectedTab: AppTab = .home
    @AppStorage("gymRepCoach.progressionIncrementPounds") private var progressionIncrementPounds = 5.0
    @FocusState private var isWeightFieldFocused: Bool

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 18) {
                        pageHeader
                        if activeRoutine == nil {
                            planCard
                        } else {
                            routinePlanCard
                        }
                        recentWorkoutsCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                }
                .background(VibratoPalette.canvas.ignoresSafeArea())
                .toolbarBackground(VibratoPalette.canvas, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { isWeightFieldFocused = false }
                    }
                }
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(AppTab.home)

            NavigationStack { WorkoutHistoryView() }
                .tabItem { Label("Workouts", systemImage: "list.bullet.clipboard") }
                .tag(AppTab.workouts)
        }
        .tint(VibratoPalette.graphite)
        .toolbarBackground(VibratoPalette.sand, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onChange(of: connectivity.latestEvent?.timestamp) { _, _ in saveLatestEventIfNeeded() }
        .onChange(of: connectivity.completedWorkoutEvent?.timestamp) { _, _ in
            presentFeedbackForCompletedWorkout()
        }
        .onAppear {
            restoreActiveRoutine()
            presentFeedbackForCompletedWorkout()
        }
        .sheet(isPresented: $isRoutineBuilderPresented) {
            RoutineBuilderSheet(
                initialPlans: activeRoutine?.exercises ?? currentPlan.map { [$0] } ?? [],
                initialName: activeRoutine?.name
            ) { routine in
                setActiveRoutine(routine)
            }
        }
        .sheet(item: $feedbackPrompt) { prompt in
            WorkoutEffortSheet(
                event: prompt.event,
                weightIncrementPounds: progressionIncrementPounds,
                onSubmit: { repsInReserve in
                    submitEffort(repsInReserve, for: prompt.event)
                },
                onApply: apply,
                onSkip: {
                    if let workoutID = prompt.event.workoutID {
                        skippedFeedbackWorkoutIDs.insert(workoutID)
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert(item: $connectivity.planSendConfirmation) { confirmation in
            Alert(
                title: Text(confirmation.title),
                message: Text(confirmation.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NEXT WORKOUT")
                .font(.caption.weight(.bold))
                .tracking(1.8)
                .foregroundStyle(VibratoPalette.muted)

            if let activeRoutine {
                Text(activeRoutine.name)
                    .font(.system(.largeTitle, design: .default, weight: .bold))
                    .foregroundStyle(VibratoPalette.graphite)
                Text("\(activeRoutine.exercises.count) exercises · \(activeRoutine.totalTargetSets) total sets")
                    .font(.subheadline)
                    .foregroundStyle(VibratoPalette.muted)
            } else {
                Menu {
                    Picker("Exercise", selection: $exercise) {
                        ForEach(ExerciseKind.armExercises) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                } label: {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            exerciseTitle
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(VibratoPalette.muted)
                            Spacer()
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            exerciseTitle
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(VibratoPalette.muted)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Exercise, \(exercise.displayName)")
                .accessibilityHint("Choose a different exercise")

                Text(planSummary)
                    .font(.subheadline)
                    .foregroundStyle(VibratoPalette.muted)
            }

            VibratoResonanceRule()
                .padding(.top, 2)
        }
    }

    private var planCard: some View {
        VStack(spacing: 0) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 12) {
                        PlanCounter(title: "Sets", value: $targetSets, range: 1...10)
                        Divider().overlay(VibratoPalette.line)
                        PlanCounter(title: "Reps", value: $targetReps, range: 1...50)
                    }
                } else {
                    HStack(spacing: 12) {
                        PlanCounter(title: "Sets", value: $targetSets, range: 1...10)
                        Divider().overlay(VibratoPalette.line).frame(height: 82)
                        PlanCounter(title: "Reps", value: $targetReps, range: 1...50)
                    }
                }
            }
            .padding(.bottom, 16)

            Divider().overlay(VibratoPalette.line)

            Button {
                isWeightFieldFocused = false
                isRoutineBuilderPresented = true
            } label: {
                Label("Build a Routine", systemImage: "list.bullet.rectangle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(VibratoPalette.sand, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.top, 16)

            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Weight").font(.subheadline.weight(.semibold))
                            weightInput
                        }
                    } else {
                        HStack {
                            Text("Weight").font(.subheadline.weight(.semibold))
                            Spacer()
                            weightInput
                        }
                    }
                }

                if let weightValidationMessage {
                    Label(weightValidationMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(VibratoPalette.error)
                }
            }
            .padding(.vertical, 16)

            Divider().overlay(VibratoPalette.line)

            DisclosureGroup(isExpanded: $isWorkoutOptionsExpanded) {
                VStack(spacing: 14) {
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Rest between sets")
                                restPicker
                            }
                        } else {
                            HStack {
                                Text("Rest between sets")
                                Spacer()
                                restPicker
                            }
                        }
                    }

                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Progression step")
                                progressionPicker
                            }
                        } else {
                            HStack {
                                Text("Progression step")
                                Spacer()
                                progressionPicker
                            }
                        }
                    }
                }
                .font(.subheadline)
                .foregroundStyle(VibratoPalette.graphite)
                .padding(.top, 16)
            } label: {
                Text("Workout options")
                    .font(.subheadline.weight(.semibold))
            }
            .tint(VibratoPalette.graphite)
            .padding(.vertical, 16)

            Button {
                isWeightFieldFocused = false
                guard let currentPlan else { return }
                connectivity.send(plan: currentPlan)
            } label: {
                ZStack {
                    Text("Send to Watch")
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                }
                .font(.headline)
                .foregroundStyle(VibratoPalette.sandLight)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(VibratoPalette.graphite, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(currentPlan == nil)
            .opacity(currentPlan == nil ? 0.45 : 1)

            watchStatusLine
                .padding(.top, 13)
        }
        .foregroundStyle(VibratoPalette.graphite)
        .padding(20)
        .vibratoSurface(cornerRadius: 20)
    }

    private var routinePlanCard: some View {
        VStack(spacing: 0) {
            if let activeRoutine {
                ForEach(Array(activeRoutine.exercises.enumerated()), id: \.element.id) { index, plan in
                    if index > 0 { Divider().overlay(VibratoPalette.line) }
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .frame(width: 28, height: 28)
                            .background(VibratoPalette.sand, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(plan.exercise.displayName).font(.headline)
                            Text("\(plan.targetSets) × \(plan.targetReps) · \(plan.weightPounds.formatted(.number.precision(.fractionLength(1)))) lb")
                                .font(.caption).foregroundStyle(VibratoPalette.muted)
                        }
                        Spacer()
                        Text(plan.formattedRestDuration)
                            .font(.caption2).foregroundStyle(VibratoPalette.muted)
                    }
                    .padding(.vertical, 12)
                }
            }

            HStack(spacing: 10) {
                Button("Edit Routine") { isRoutineBuilderPresented = true }
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(VibratoPalette.sand, in: RoundedRectangle(cornerRadius: 12))
                Button("Use Single") { clearActiveRoutine() }
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .overlay { RoundedRectangle(cornerRadius: 12).stroke(VibratoPalette.line) }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.plain)
            .padding(.top, 16)

            Button {
                guard let activeRoutine else { return }
                connectivity.send(routine: activeRoutine)
            } label: {
                ZStack {
                    Text("Send Routine to Watch")
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                }
                .font(.headline)
                .foregroundStyle(VibratoPalette.sandLight)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(VibratoPalette.graphite, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.top, 12)

            watchStatusLine.padding(.top, 13)
        }
        .foregroundStyle(VibratoPalette.graphite)
        .padding(20)
        .vibratoSurface(cornerRadius: 20)
    }

    private var watchStatusLine: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 5) {
                    watchConnectionLabel
                    latestSetLabel
                }
            } else {
                HStack(spacing: 8) {
                    watchConnectionLabel
                    Spacer()
                    latestSetLabel
                }
            }
        }
        .font(.caption)
        .foregroundStyle(VibratoPalette.muted)
    }

    private var exerciseTitle: some View {
        Text(exercise.displayName)
            .font(.system(.largeTitle, design: .default, weight: .bold))
            .foregroundStyle(VibratoPalette.graphite)
    }

    private var weightInput: some View {
        HStack(spacing: 6) {
            TextField("0", value: $weightPounds, format: .number.precision(.fractionLength(1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($isWeightFieldFocused)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .frame(minWidth: 82, maxWidth: 120)
                .accessibilityLabel("Weight in pounds")
                .accessibilityHint("Enter a number greater than zero")
            Text("lb")
                .font(.subheadline)
                .foregroundStyle(VibratoPalette.muted)
        }
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .trailing)
    }

    private var restPicker: some View {
        Picker("Rest", selection: $restDurationSeconds) {
            ForEach([0, 15, 30, 45, 60, 90, 120, 180], id: \.self) { seconds in
                Text(ExercisePlan.formattedRestDuration(seconds: seconds)).tag(seconds)
            }
        }
        .labelsHidden()
    }

    private var progressionPicker: some View {
        Picker("Progression step", selection: $progressionIncrementPounds) {
            ForEach([2.5, 5.0, 10.0], id: \.self) { pounds in
                Text("\(pounds, specifier: "%g") lb").tag(pounds)
            }
        }
        .labelsHidden()
    }

    private var watchConnectionLabel: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connectivity.isWatchReachable ? VibratoPalette.success : VibratoPalette.muted)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(connectivity.isWatchReachable ? "Watch app ready" : "Will sync when Watch is available")
        }
    }

    @ViewBuilder
    private var latestSetLabel: some View {
        if let event = connectivity.latestEvent {
            Text("Last set · \(event.repetitions) reps")
        }
    }

    private var recentWorkoutsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent workouts")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(VibratoPalette.graphite)

                Spacer()

                if !workouts.isEmpty {
                    Button("See all") { selectedTab = .workouts }
                        .font(.subheadline.weight(.semibold))
                }
            }

            if workouts.isEmpty {
                Text("Finish your first set on Apple Watch to start tracking progress.")
                    .font(.subheadline)
                    .foregroundStyle(VibratoPalette.muted)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 20)
            } else {
                if let latestRoutine = workouts.first?.repeatedRoutine {
                    Button {
                        setActiveRoutine(latestRoutine)
                        connectivity.send(routine: latestRoutine)
                    } label: {
                        HStack {
                            Label("Repeat Last Workout", systemImage: "arrow.clockwise")
                            Spacer()
                            Image(systemName: "applewatch")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(VibratoPalette.sand, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                VStack(spacing: 0) {
                    ForEach(Array(workouts.prefix(3).enumerated()), id: \.element.id) { index, workout in
                        if index > 0 { Divider().overlay(VibratoPalette.line) }
                        RecentWorkoutRow(workout: workout).padding(.vertical, 13)
                    }
                }
            }
        }
    }

    private var workouts: [WorkoutSummary] {
        WorkoutHistoryGrouping.workouts(from: history.records)
            .sorted { $0.completedAt > $1.completedAt }
    }

    private var planSummary: String {
        let weight = validWeightPounds.map {
            "\($0.formatted(.number.precision(.fractionLength(1)))) lb"
        } ?? "Add weight"
        return "\(targetSets) sets × \(targetReps) reps · \(weight)"
    }

    private var validWeightPounds: Double? {
        guard let weightPounds, weightPounds.isFinite, weightPounds > 0 else { return nil }
        return weightPounds
    }

    private var weightValidationMessage: String? {
        guard weightPounds != nil else { return "Enter a weight." }
        guard validWeightPounds != nil else { return "Weight must be greater than 0 lb." }
        return nil
    }

    private var currentPlan: ExercisePlan? {
        guard let validWeightPounds else { return nil }
        return ExercisePlan(
            exercise: exercise,
            targetSets: targetSets,
            targetReps: targetReps,
            weightKilograms: WeightConversion.kilograms(fromPounds: validWeightPounds),
            restDurationSeconds: restDurationSeconds
        )
    }

    private func saveLatestEventIfNeeded() {
        guard let event = connectivity.latestEvent, event.timestamp != savedEventTimestamp else { return }
        history.append(event: event)
        savedEventTimestamp = event.timestamp
    }

    private func presentFeedbackForCompletedWorkout() {
        guard let event = connectivity.completedWorkoutEvent,
              let workoutID = event.workoutID else { return }
        history.append(event: event)
        guard !skippedFeedbackWorkoutIDs.contains(workoutID) else { return }
        guard !history.records.contains(where: {
            $0.workoutID == workoutID && $0.repsInReserve != nil
        }) else { return }
        feedbackPrompt = WorkoutFeedbackPrompt(event: event)
    }

    private func submitEffort(
        _ repsInReserve: Int,
        for event: SetCompletedEvent
    ) -> ProgressionRecommendation? {
        guard let workoutID = event.workoutID else { return nil }
        history.recordEffort(repsInReserve: repsInReserve, for: workoutID, exercise: event.exercise)
        return AdaptiveProgressionEngine.recommendation(
            for: workoutID,
            in: history.records,
            weightIncrementPounds: progressionIncrementPounds
        )
    }

    private func apply(_ recommendation: ProgressionRecommendation) {
        guard let recommendedWeight = recommendation.recommendedWeightPounds else { return }
        exercise = recommendation.exercise
        weightPounds = recommendedWeight
        if let sets = recommendation.targetSets { targetSets = sets }
        if let reps = recommendation.targetRepetitions { targetReps = reps }
        if let rest = recommendation.restDurationSeconds { restDurationSeconds = rest }
        clearActiveRoutine()
    }

    private func setActiveRoutine(_ routine: WorkoutRoutine) {
        activeRoutine = routine
        if let data = try? JSONEncoder().encode(routine) {
            UserDefaults.standard.set(data, forKey: "gymRepCoach.activeRoutine.v1")
        }
    }

    private func clearActiveRoutine() {
        activeRoutine = nil
        UserDefaults.standard.removeObject(forKey: "gymRepCoach.activeRoutine.v1")
    }

    private func restoreActiveRoutine() {
        guard activeRoutine == nil,
              let data = UserDefaults.standard.data(forKey: "gymRepCoach.activeRoutine.v1"),
              let routine = try? JSONDecoder().decode(WorkoutRoutine.self, from: data),
              !routine.exercises.isEmpty else { return }
        activeRoutine = routine
    }
}

private enum AppTab: Hashable {
    case home
    case workouts
}

private struct WorkoutFeedbackPrompt: Identifiable {
    let id: UUID
    let event: SetCompletedEvent

    init(event: SetCompletedEvent) {
        id = event.workoutID ?? UUID()
        self.event = event
    }
}

private struct WorkoutEffortSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let event: SetCompletedEvent
    let weightIncrementPounds: Double
    let onSubmit: (Int) -> ProgressionRecommendation?
    let onApply: (ProgressionRecommendation) -> Void
    let onSkip: () -> Void

    @State private var recommendation: ProgressionRecommendation?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if let recommendation {
                        recommendationView(recommendation)
                    } else {
                        effortQuestion
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(VibratoPalette.canvas.ignoresSafeArea())
            .navigationTitle(recommendation == nil ? "Workout complete" : "Next workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(recommendation == nil ? "Skip" : "Done") {
                        if recommendation == nil { onSkip() }
                        dismiss()
                    }
                }
            }
        }
    }

    private var effortQuestion: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(VibratoPalette.success)

            VStack(spacing: 7) {
                Text(event.exercise.displayName)
                    .font(.title2.bold())
                Text("How many more clean reps could you have completed at the end?")
                    .font(.subheadline)
                    .foregroundStyle(VibratoPalette.muted)
                    .multilineTextAlignment(.center)
            }

            LazyVGrid(columns: effortColumns, spacing: 8) {
                ForEach(0...4, id: \.self) { value in
                    Button {
                        recommendation = onSubmit(value)
                    } label: {
                        VStack(spacing: 3) {
                            Text(value == 4 ? "4+" : "\(value)")
                                .font(.title3.bold())
                            Text("left")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(VibratoPalette.graphite)
                        .background(VibratoPalette.sand, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(EffortTileButtonStyle())
                    .accessibilityLabel(value == 4 ? "4 or more reps left" : "\(value) reps left")
                }
            }

            Text("Your answer is used with recent workouts to make a conservative recommendation.")
                .font(.caption)
                .foregroundStyle(VibratoPalette.muted)
                .multilineTextAlignment(.center)
        }
    }

    private var effortColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 8),
            count: dynamicTypeSize.isAccessibilitySize ? 3 : 5
        )
    }

    private func recommendationView(_ recommendation: ProgressionRecommendation) -> some View {
        VStack(spacing: 18) {
            Image(systemName: recommendationIcon(for: recommendation.action))
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(VibratoPalette.graphite)
                .frame(width: 72, height: 72)
                .background(VibratoPalette.sand, in: Circle())

            VStack(spacing: 8) {
                Text(recommendation.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(recommendation.explanation)
                    .font(.subheadline)
                    .foregroundStyle(VibratoPalette.muted)
                    .multilineTextAlignment(.center)
            }

            if let weight = recommendation.recommendedWeightPounds {
                Button {
                    onApply(recommendation)
                    dismiss()
                } label: {
                    Text("Use \(weight.formatted(.number.precision(.fractionLength(1)))) lb next time")
                        .font(.headline)
                        .foregroundStyle(VibratoPalette.sandLight)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                        .background(VibratoPalette.graphite, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)

                Text("Based on your \(weightIncrementPounds.formatted(.number.precision(.fractionLength(1)))) lb progression step")
                    .font(.caption)
                    .foregroundStyle(VibratoPalette.muted)
            } else {
                Button { dismiss() } label: {
                    Text("Done")
                        .font(.headline)
                        .foregroundStyle(VibratoPalette.sandLight)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                        .background(VibratoPalette.graphite, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func recommendationIcon(for action: ProgressionAction) -> String {
        switch action {
        case .increase: "arrow.up.right"
        case .maintain: "equal"
        case .decrease: "arrow.down.right"
        }
    }
}

private struct EffortTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct VibratoResonanceRule: View {
    var body: some View {
        HStack(spacing: 7) {
            Rectangle()
                .fill(VibratoPalette.line)
                .frame(height: 1)

            ZStack {
                Circle()
                    .stroke(VibratoPalette.sandDark, lineWidth: 1)
                    .frame(width: 15, height: 15)
                Capsule()
                    .fill(VibratoPalette.sandDark)
                    .frame(width: 27, height: 1)
                Capsule()
                    .fill(VibratoPalette.sandDark)
                    .frame(width: 1, height: 15)
            }
            .frame(width: 28, height: 16)

            Rectangle()
                .fill(VibratoPalette.line)
                .frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct PlanCounter: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        VStack(spacing: 10) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(VibratoPalette.muted)
            HStack(spacing: 12) {
                counterButton("minus", disabled: value <= range.lowerBound) {
                    value = max(range.lowerBound, value - 1)
                }
                Text("\(value)")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .frame(minWidth: 30)
                counterButton("plus", disabled: value >= range.upperBound) {
                    value = min(range.upperBound, value + 1)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func counterButton(_ image: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.caption.weight(.bold))
                .frame(width: 44, height: 44)
                .background(VibratoPalette.sand, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .accessibilityLabel("\(image == "plus" ? "Increase" : "Decrease") \(title.lowercased())")
        .accessibilityValue("\(value)")
    }
}

private struct RecentWorkoutRow: View {
    let workout: WorkoutSummary
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    workoutIdentity
                    workoutSummary
                }
            } else {
                HStack(spacing: 14) {
                    workoutIdentity
                    Spacer()
                    workoutSummary
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var workoutIdentity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(workout.exerciseName).font(.headline)
            Text(workout.completedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption).foregroundStyle(VibratoPalette.muted)
        }
    }

    private var workoutSummary: some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 4) {
            Text("\(workout.totalRepetitions) reps").font(.subheadline.weight(.semibold))
            Text("\(workout.sets.count) sets · \(weightDescription)")
                .font(.caption).foregroundStyle(VibratoPalette.muted)
        }
    }

    private var weightDescription: String {
        guard let weight = workout.weightPounds else { return "Mixed" }
        return "\(weight.formatted(.number.precision(.fractionLength(1)))) lb"
    }
}

private struct WorkoutHistoryView: View {
    @EnvironmentObject private var history: WorkoutHistoryStore
    @State private var sortOrder: WorkoutSortOrder = .newestFirst

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if !personalRecords.isEmpty {
                    PersonalRecordsSection(records: personalRecords)
                }

                if workouts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "waveform.path")
                            .font(.largeTitle).foregroundStyle(VibratoPalette.sandDark)
                        Text("No workouts yet").font(.headline)
                        Text("Finish a set on your Watch to start your history.")
                            .font(.subheadline)
                            .foregroundStyle(VibratoPalette.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 90)
                } else {
                    ForEach(workouts) { WorkoutCard(workout: $0) }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(VibratoPalette.canvas.ignoresSafeArea())
        .navigationTitle("Workouts")
        .toolbarBackground(VibratoPalette.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Chronological order", selection: $sortOrder) {
                        ForEach(WorkoutSortOrder.allCases) { order in
                            Label(order.title, systemImage: order.systemImage).tag(order)
                        }
                    }
                } label: {
                    Label("Sort workouts", systemImage: "arrow.up.arrow.down")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel("Sort workouts")
                .accessibilityValue(sortOrder.title)
            }
        }
    }

    private var workouts: [WorkoutSummary] {
        WorkoutHistoryGrouping.workouts(from: history.records).sorted {
            sortOrder == .newestFirst ? $0.completedAt > $1.completedAt : $0.completedAt < $1.completedAt
        }
    }

    private var personalRecords: [ExercisePersonalRecord] {
        PersonalRecordEngine.records(from: history.records)
    }
}

private struct PersonalRecordsSection: View {
    let records: [ExercisePersonalRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Personal Records", systemImage: "trophy.fill")
                    .font(.title3.bold())
                Spacer()
                Text("Estimated 1RM")
                    .font(.caption)
                    .foregroundStyle(VibratoPalette.muted)
            }

            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                if index > 0 { Divider().overlay(VibratoPalette.line) }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(record.exercise.displayName).font(.headline)
                        Spacer()
                        Text("\(record.estimatedOneRepMaxPounds.formatted(.number.precision(.fractionLength(1)))) lb")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .monospacedDigit()
                    }
                    HStack {
                        Label("Heaviest \(record.heaviestWeightPounds.formatted(.number.precision(.fractionLength(1)))) lb", systemImage: "scalemass")
                        Spacer()
                        Label("Best set \(record.mostRepetitions) reps", systemImage: "repeat")
                    }
                    .font(.caption)
                    .foregroundStyle(VibratoPalette.muted)
                }
            }
        }
        .foregroundStyle(VibratoPalette.graphite)
        .padding(18)
        .vibratoSurface(cornerRadius: 20)
    }
}

private struct WorkoutCard: View {
    let workout: WorkoutSummary
    @State private var isExpanded = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 0) {
                Divider().overlay(VibratoPalette.line).padding(.top, 14)
                ForEach(Array(workout.sets.enumerated()), id: \.element.id) { index, set in
                    if index > 0 { Divider().overlay(VibratoPalette.line) }
                    WorkoutSetLine(record: set).padding(.vertical, 12)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) {
                            workoutHeading
                            workoutRepTotal
                        }
                    } else {
                        HStack(alignment: .firstTextBaseline) {
                            workoutHeading
                            Spacer()
                            workoutRepTotal
                        }
                    }
                }

                Text("\(workout.sets.count) sets · \(weightDescription) · \(workout.totalDuration.formattedWorkoutDuration)")
                    .font(.subheadline)
                    .foregroundStyle(VibratoPalette.muted)

                Text(heartRateDescription)
                    .font(.caption)
                    .foregroundStyle(VibratoPalette.muted)
                if let repsInReserve = workout.repsInReserve {
                    Text(repsInReserve == 4 ? "4+ clean reps left" : "\(repsInReserve) clean reps left")
                        .font(.caption)
                        .foregroundStyle(VibratoPalette.muted)
                }

                Text(isExpanded ? "Hide sets" : "Show sets")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VibratoPalette.graphite)
            }
        }
        .tint(VibratoPalette.graphite)
        .accessibilityHint(isExpanded ? "Collapses the set details" : "Expands the set details")
        .padding(18)
        .vibratoSurface(cornerRadius: 20)
    }

    private var workoutHeading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(workout.exerciseName).font(.headline)
            Text(workout.completedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption).foregroundStyle(VibratoPalette.muted)
        }
    }

    private var workoutRepTotal: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(workout.totalRepetitions)")
                .font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
            Text("reps").font(.caption).foregroundStyle(VibratoPalette.muted)
        }
    }

    private var weightDescription: String {
        guard let weight = workout.weightPounds else { return "Mixed" }
        return "\(weight.formatted(.number.precision(.fractionLength(1)))) lb"
    }

    private var heartRateDescription: String {
        guard let rate = workout.averageHeartRate else { return "Heart rate not recorded" }
        return "Average heart rate · \(Int(rate.rounded())) bpm"
    }
}

private struct WorkoutSetLine: View {
    let record: WorkoutSetRecord
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    setIdentity
                    setSummary
                }
            } else {
                HStack {
                    setIdentity
                    Spacer()
                    setSummary
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var setIdentity: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(record.exerciseName) · Set \(record.setNumber)").font(.subheadline.weight(.semibold))
            Text(record.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption2).foregroundStyle(VibratoPalette.muted)
        }
    }

    private var setSummary: some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
            Text("\(record.repetitions) reps · \(record.weightPounds, specifier: "%.1f") lb")
                .font(.caption.weight(.medium))
            HStack(spacing: 8) {
                Text(record.formattedDuration)
                if let rate = record.averageHeartRate {
                    Label("\(Int(rate.rounded()))", systemImage: "heart")
                }
            }
            .font(.caption2).foregroundStyle(VibratoPalette.muted)
        }
    }
}

private enum WorkoutSortOrder: String, CaseIterable, Identifiable {
    case newestFirst, oldestFirst
    var id: String { rawValue }
    var title: String { self == .newestFirst ? "Newest first" : "Oldest first" }
    var systemImage: String { self == .newestFirst ? "arrow.down" : "arrow.up" }
}

enum VibratoPalette {
    static let canvas = adaptive(
        light: rgb(0.91, 0.89, 0.84), dark: rgb(0.11, 0.12, 0.11),
        increasedLight: rgb(0.96, 0.94, 0.89), increasedDark: rgb(0.05, 0.06, 0.05)
    )
    static let surface = adaptive(
        light: rgb(0.97, 0.96, 0.92), dark: rgb(0.18, 0.19, 0.18),
        increasedLight: rgb(1.00, 0.99, 0.96), increasedDark: rgb(0.23, 0.24, 0.23)
    )
    static let sand = adaptive(
        light: rgb(0.82, 0.76, 0.65), dark: rgb(0.25, 0.26, 0.24),
        increasedLight: rgb(0.75, 0.67, 0.54), increasedDark: rgb(0.32, 0.33, 0.30)
    )
    static let sandLight = adaptive(
        light: rgb(0.93, 0.89, 0.80), dark: rgb(0.16, 0.17, 0.16),
        increasedLight: rgb(0.99, 0.96, 0.89), increasedDark: rgb(0.08, 0.09, 0.08)
    )
    static let sandDark = adaptive(
        light: rgb(0.52, 0.45, 0.35), dark: rgb(0.82, 0.76, 0.65),
        increasedLight: rgb(0.36, 0.30, 0.22), increasedDark: rgb(0.90, 0.84, 0.73)
    )
    static let graphite = adaptive(
        light: rgb(0.16, 0.17, 0.16), dark: rgb(0.93, 0.89, 0.80),
        increasedLight: rgb(0.07, 0.08, 0.07), increasedDark: rgb(0.99, 0.96, 0.89)
    )
    static let muted = adaptive(
        light: rgb(0.38, 0.39, 0.36), dark: rgb(0.68, 0.64, 0.56),
        increasedLight: rgb(0.24, 0.25, 0.22), increasedDark: rgb(0.82, 0.77, 0.68)
    )
    static let line = adaptive(
        light: rgb(0.16, 0.17, 0.16, 0.10), dark: rgb(0.93, 0.89, 0.80, 0.14),
        increasedLight: rgb(0.07, 0.08, 0.07, 0.24), increasedDark: rgb(0.99, 0.96, 0.89, 0.28)
    )
    static let success = adaptive(
        light: rgb(0.32, 0.45, 0.34), dark: rgb(0.57, 0.70, 0.55),
        increasedLight: rgb(0.17, 0.34, 0.20), increasedDark: rgb(0.70, 0.84, 0.67)
    )
    static let error = adaptive(
        light: rgb(0.55, 0.20, 0.17), dark: rgb(0.90, 0.52, 0.45),
        increasedLight: rgb(0.40, 0.08, 0.06), increasedDark: rgb(1.00, 0.68, 0.60)
    )

    private static func adaptive(
        light: UIColor,
        dark: UIColor,
        increasedLight: UIColor,
        increasedDark: UIColor
    ) -> Color {
        Color(uiColor: UIColor { traits in
            switch (traits.userInterfaceStyle, traits.accessibilityContrast) {
            case (.dark, .high): increasedDark
            case (.dark, _): dark
            case (_, .high): increasedLight
            default: light
            }
        })
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

extension View {
    func vibratoSurface(cornerRadius: CGFloat) -> some View {
        background(VibratoPalette.surface, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(VibratoPalette.line, lineWidth: 1)
            }
    }
}

private extension TimeInterval {
    var formattedWorkoutDuration: String {
        let totalSeconds = max(0, Int(rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
    }
}

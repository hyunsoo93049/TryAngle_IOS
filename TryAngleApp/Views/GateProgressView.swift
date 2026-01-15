//
//  GateProgressView.swift
//  Gate System 단계 표시 뷰
//  4단계: 비율 → 프레이밍 → 위치 → 압축감 (포즈 제외)
//

import SwiftUI

// MARK: - Gate 진행 상태 뷰
struct GateProgressView: View {
    let evaluation: GateEvaluation?

    // 🆕 Gate 정보 (포즈 제외 - 4단계만)
    private let gates: [String] = [
        "비율",
        "프레이밍",
        "위치",
        "압축감"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 헤더
            HStack {
                Text("Gate System")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))

                Spacer()

                // 🆕 통과 개수 (4개 중)
                if let eval = evaluation {
                    Text("\(passedCountWithoutPose(eval))/4")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(allPassedWithoutPose(eval) ? .green : .white)
                }
            }

            // 🆕 4단계만 표시 (포즈 제외)
            ForEach(0..<4, id: \.self) { index in
                GateStepView(
                    index: index,
                    name: gates[index],
                    state: gateState(for: index),
                    isCurrentGate: isCurrentGate(index)
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.7))
        )
    }

    // 🆕 포즈 제외한 통과 개수
    private func passedCountWithoutPose(_ eval: GateEvaluation) -> Int {
        return [eval.gate0, eval.gate1, eval.gate2, eval.gate3].filter { $0.passed }.count
    }

    // 🆕 포즈 제외하고 모두 통과 여부
    private func allPassedWithoutPose(_ eval: GateEvaluation) -> Bool {
        return eval.gate0.passed && eval.gate1.passed && eval.gate2.passed && eval.gate3.passed
    }

    // 🆕 Gate 상태 계산 - 실제 상태 표시 (순차적 진행 아님)
    private func gateState(for index: Int) -> GateStepState {
        guard let eval = evaluation else { return .pending }

        let passed: Bool
        switch index {
        case 0: passed = eval.gate0.passed
        case 1: passed = eval.gate1.passed
        case 2: passed = eval.gate2.passed
        case 3: passed = eval.gate3.passed
        default: passed = false
        }

        if passed {
            return .passed
        } else {
            // 🆕 실패한 Gate는 모두 .failed로 표시 (pending 대신)
            return .failed
        }
    }

    // 현재 Gate인지 확인 (첫 번째 미통과 Gate)
    private func isCurrentGate(_ index: Int) -> Bool {
        guard let eval = evaluation else { return index == 0 }
        // 🆕 Gate 4(포즈)는 제외하므로 currentFailedGate가 4면 무시
        guard let failedGate = eval.currentFailedGate, failedGate < 4 else { return false }
        return failedGate == index
    }
}

// MARK: - Gate 단계 상태
enum GateStepState {
    case passed   // 통과
    case failed   // 🆕 실패 (이전 Gate와 무관하게 실패 표시)
    case pending  // 대기 중 (evaluation 없을 때)
}

// MARK: - 개별 Gate 단계 뷰
struct GateStepView: View {
    let index: Int
    let name: String
    let state: GateStepState
    let isCurrentGate: Bool

    var body: some View {
        HStack(spacing: 8) {
            // 단계 번호 또는 체크/X
            ZStack {
                Circle()
                    .fill(circleColor)
                    .frame(width: 20, height: 20)

                if state == .passed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                } else if state == .failed {
                    // 🆕 실패 표시 (X 또는 번호)
                    if isCurrentGate {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.black)
                    } else {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            // 이름 표시
            Text(name)
                .font(.system(size: 13, weight: isCurrentGate ? .bold : .medium))
                .foregroundColor(textColor)

            Spacer()

            // 🆕 현재 단계 표시 (첫 번째 실패 Gate)
            if isCurrentGate {
                Text("현재")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.yellow)
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 2)
    }

    private var circleColor: Color {
        switch state {
        case .passed: return .green
        case .failed:
            return isCurrentGate ? .yellow : .red.opacity(0.7)  // 🆕 실패는 빨간색
        case .pending: return .white.opacity(0.2)
        }
    }

    private var textColor: Color {
        switch state {
        case .passed: return .green
        case .failed:
            return isCurrentGate ? .white : .red.opacity(0.8)  // 🆕 실패는 빨간색
        case .pending: return .white.opacity(0.5)
        }
    }
}

// MARK: - Preview
struct GateProgressView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                // 테스트용 - Gate 2까지 통과
                GateProgressView(evaluation: nil)
                    .frame(width: 160)
            }
        }
    }
}

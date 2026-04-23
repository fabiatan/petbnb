import SwiftUI

struct BookingPlaceholderView: View {
    let business: BusinessSummary
    let kennel: KennelTypeSummary
    let criteria: SearchCriteria

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "pawprint.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Coming in Phase 2c")
                .font(.title2).fontWeight(.semibold)
            Text(
                "The booking request flow lands here. For now, you've picked:\n"
                + "\(business.name) · \(kennel.name) · "
                + "\(criteria.checkIn.formatted(date: .abbreviated, time: .omitted)) → "
                + "\(criteria.checkOut.formatted(date: .abbreviated, time: .omitted))."
            )
            .multilineTextAlignment(.center)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
        }
        .padding()
        .navigationTitle("Continue")
    }
}

import SwiftUI

struct ConnectionRowView: View {
    let connection: Connection

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(connection.accentColor)
                .frame(width: 4, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text("\(connection.username)@\(connection.host)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

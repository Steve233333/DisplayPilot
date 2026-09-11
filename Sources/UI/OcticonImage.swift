import SwiftUI

/// Octicons 图标（资源目录里的矢量模板图，跟随前景色）。
struct OcticonImage: View {
    let name: String
    var size: CGFloat = 14

    var body: some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

/// 统一的小徽标样式。
struct Badge: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(tint.opacity(0.16))
            )
            .foregroundStyle(tint)
    }
}

/// 卡片容器：圆角 + 细边 + 轻材质，深浅色都好看。
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.separator.opacity(0.5), lineWidth: 1)
            )
    }
}

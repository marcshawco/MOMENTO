import SwiftUI

/// Segmented tab container routing to Photos, Voice Memos, and Notes tabs.
struct AttachmentsSection: View {

    @Bindable var viewModel: ItemDetailViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Attachments", selection: $viewModel.activeAttachmentTab) {
                ForEach(AttachmentTab.allCases) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            switch viewModel.activeAttachmentTab {
            case .photos:
                PhotosTabView(viewModel: viewModel)
            case .voiceMemos:
                VoiceMemosTabView(viewModel: viewModel)
            case .notes:
                NotesTabView(viewModel: viewModel)
            }
        }
    }
}

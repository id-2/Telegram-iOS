import Foundation
import UIKit
import Display
import AsyncDisplayKit
import AnimatedStickerNode
import TelegramAnimatedStickerNode
import SwiftSignalKit
import AccountContext
import YuvConversion
import TelegramCore
import Postbox
import AnimationCache
import LottieAnimationCache
import VideoAnimationCache
import MultiAnimationRenderer
import ShimmerEffect
import TextFormat

public final class InlineStickerItemLayer: MultiAnimationRenderTarget {
    public static let queue = Queue()
    
    public struct Key: Hashable {
        public var id: Int64
        public var index: Int
        
        public init(id: Int64, index: Int) {
            self.id = id
            self.index = index
        }
    }
    
    private let context: AccountContext
    private let groupId: String
    private let emoji: ChatTextInputTextCustomEmojiAttribute
    private let cache: AnimationCache
    private let renderer: MultiAnimationRenderer
    private let placeholderColor: UIColor
    
    private let pointSize: CGSize
    private let pixelSize: CGSize
    
    private var file: TelegramMediaFile?
    private var infoDisposable: Disposable?
    private var disposable: Disposable?
    private var fetchDisposable: Disposable?
    private var loadDisposable: Disposable?
    
    private var isInHierarchyValue: Bool = false
    public var isVisibleForAnimations: Bool = false {
        didSet {
            if self.isVisibleForAnimations != oldValue {
                self.updatePlayback()
            }
        }
    }
    
    public init(context: AccountContext, groupId: String, attemptSynchronousLoad: Bool, emoji: ChatTextInputTextCustomEmojiAttribute, cache: AnimationCache, renderer: MultiAnimationRenderer, placeholderColor: UIColor, pointSize: CGSize) {
        self.context = context
        self.groupId = groupId
        self.emoji = emoji
        self.cache = cache
        self.renderer = renderer
        self.placeholderColor = placeholderColor
        
        let scale = min(2.0, UIScreenScale)
        self.pointSize = pointSize
        self.pixelSize = CGSize(width: self.pointSize.width * scale, height: self.pointSize.height * scale)
        
        super.init()
        
        self.infoDisposable = (context.engine.stickers.loadedStickerPack(reference: emoji.stickerPack, forceActualized: false)
        |> deliverOnMainQueue).start(next: { [weak self] result in
            guard let strongSelf = self else {
                return
            }
            switch result {
            case let .result(_, items, _):
                for item in items {
                    if item.file.fileId.id == emoji.fileId {
                        strongSelf.updateFile(file: item.file, attemptSynchronousLoad: false)
                        break
                    }
                }
            default:
                break
            }
        })
    }
    
    override public init(layer: Any) {
        preconditionFailure()
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.loadDisposable?.dispose()
        self.infoDisposable?.dispose()
        self.disposable?.dispose()
        self.fetchDisposable?.dispose()
    }
    
    override public func action(forKey event: String) -> CAAction? {
        if event == kCAOnOrderIn {
            self.isInHierarchyValue = true
        } else if event == kCAOnOrderOut {
            self.isInHierarchyValue = false
        }
        self.updatePlayback()
        return nullAction
    }
    
    private func updatePlayback() {
        let shouldBePlaying = self.isInHierarchyValue && self.isVisibleForAnimations
        
        self.shouldBeAnimating = shouldBePlaying
    }
    
    private func updateFile(file: TelegramMediaFile, attemptSynchronousLoad: Bool) {
        if self.file?.fileId == file.fileId {
            return
        }
        
        self.file = file
        
        if attemptSynchronousLoad {
            if !self.renderer.loadFirstFrameSynchronously(groupId: self.groupId, target: self, cache: self.cache, itemId: file.resource.id.stringRepresentation, size: self.pixelSize) {
                if let image = generateStickerPlaceholderImage(data: file.immediateThumbnailData, size: self.pointSize, imageSize: file.dimensions?.cgSize ?? CGSize(width: 512.0, height: 512.0), backgroundColor: nil, foregroundColor: self.placeholderColor) {
                    self.contents = image.cgImage
                }
            }
            
            self.loadAnimation()
        } else {
            self.loadDisposable = self.renderer.loadFirstFrame(groupId: self.groupId, target: self, cache: self.cache, itemId: file.resource.id.stringRepresentation, size: self.pixelSize, completion: { [weak self] _ in
                self?.loadAnimation()
            })
            self.loadAnimation()
        }
    }
    
    private func loadAnimation() {
        guard let file = self.file else {
            return
        }
        
        let context = self.context
        self.disposable = renderer.add(groupId: self.groupId, target: self, cache: self.cache, itemId: file.resource.id.stringRepresentation, size: self.pixelSize, fetch: { size, writer in
            let source = AnimatedStickerResourceSource(account: context.account, resource: file.resource, fitzModifier: nil, isVideo: false)
            
            let dataDisposable = source.directDataPath(attemptSynchronously: false).start(next: { result in
                guard let result = result else {
                    return
                }
                
                if file.isVideoSticker {
                    cacheVideoAnimation(path: result, width: Int(size.width), height: Int(size.height), writer: writer)
                } else {
                    guard let data = try? Data(contentsOf: URL(fileURLWithPath: result)) else {
                        writer.finish()
                        return
                    }
                    cacheLottieAnimation(data: data, width: Int(size.width), height: Int(size.height), writer: writer)
                }
            })
            
            let fetchDisposable = freeMediaFileResourceInteractiveFetched(account: context.account, fileReference: stickerPackFileReference(file), resource: file.resource).start()
            
            return ActionDisposable {
                dataDisposable.dispose()
                fetchDisposable.dispose()
            }
        })
    }
}

public final class EmojiTextAttachmentView: UIView {
    private let contentLayer: InlineStickerItemLayer
    
    public init(context: AccountContext, emoji: ChatTextInputTextCustomEmojiAttribute, cache: AnimationCache, renderer: MultiAnimationRenderer, placeholderColor: UIColor) {
        self.contentLayer = InlineStickerItemLayer(context: context, groupId: "textInputView", attemptSynchronousLoad: true, emoji: emoji, cache: cache, renderer: renderer, placeholderColor: placeholderColor, pointSize: CGSize(width: 24.0, height: 24.0))
        
        super.init(frame: CGRect())
        
        self.layer.addSublayer(self.contentLayer)
        self.contentLayer.isVisibleForAnimations = true
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        
        self.contentLayer.frame = CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: CGSize(width: self.bounds.width, height: self.bounds.height))
    }
}

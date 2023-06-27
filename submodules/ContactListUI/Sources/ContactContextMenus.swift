import Foundation
import UIKit
import SwiftSignalKit
import ContextUI
import AccountContext
import TelegramCore
import Display
import AlertUI
import PresentationDataUtils
import OverlayStatusController
import LocalizedPeerData
import UndoUI
import TooltipUI

func contactContextMenuItems(context: AccountContext, peerId: EnginePeer.Id, contactsController: ContactsController?, isStories: Bool) -> Signal<[ContextMenuItem], NoError> {
    let strings = context.sharedContext.currentPresentationData.with({ $0 }).strings
    
    return context.engine.data.get(
        TelegramEngine.EngineData.Item.Peer.Peer(id: peerId),
        TelegramEngine.EngineData.Item.Peer.AreVoiceCallsAvailable(id: peerId),
        TelegramEngine.EngineData.Item.Peer.AreVideoCallsAvailable(id: peerId),
        TelegramEngine.EngineData.Item.Peer.NotificationSettings(id: peerId)
    )
    |> map { [weak contactsController] peer, areVoiceCallsAvailable, areVideoCallsAvailable, notificationSettings -> [ContextMenuItem] in
        var items: [ContextMenuItem] = []
        
        if isStories {
            //TODO:localize
            items.append(.action(ContextMenuActionItem(text: "View Profile", icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/User"), color: theme.contextMenu.primaryColor)
            }, action: { c, _ in
                c.dismiss(completion: {
                    let _ = (context.engine.data.get(
                        TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)
                    )
                    |> deliverOnMainQueue).start(next: { peer in
                        guard let peer = peer, let controller = context.sharedContext.makePeerInfoController(context: context, updatedPresentationData: nil, peer: peer._asPeer(), mode: .generic, avatarInitiallyExpanded: false, fromChat: false, requestsContext: nil) else {
                            return
                        }
                        (contactsController?.navigationController as? NavigationController)?.pushViewController(controller)
                    })
                })
            })))
            
            let isMuted = notificationSettings.storiesMuted == true
            items.append(.action(ContextMenuActionItem(text: isMuted ? "Notify" : "Not Notify", icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: isMuted ? "Chat/Context Menu/Unmute" : "Chat/Context Menu/Muted"), color: theme.contextMenu.primaryColor)
            }, action: { _, f in
                f(.default)
                
                let _ = context.engine.peers.togglePeerStoriesMuted(peerId: peerId).start()
                
                if let peer {
                    let iconColor = UIColor.white
                    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                    if isMuted {
                        contactsController?.present(UndoOverlayController(
                            presentationData: presentationData,
                            content: .universal(animation: "anim_profileunmute", scale: 0.075, colors: [
                                "Middle.Group 1.Fill 1": iconColor,
                                "Top.Group 1.Fill 1": iconColor,
                                "Bottom.Group 1.Fill 1": iconColor,
                                "EXAMPLE.Group 1.Fill 1": iconColor,
                                "Line.Group 1.Stroke 1": iconColor
                            ], title: nil, text: "You will now get a notification whenever **\(peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder))** posts a story.", customUndoText: nil, timeout: nil),
                            elevatedLayout: false,
                            animateInAsReplacement: false,
                            action: { _ in return false }
                        ), in: .current)
                    } else {
                        contactsController?.present(UndoOverlayController(
                            presentationData: presentationData,
                            content: .universal(animation: "anim_profilemute", scale: 0.075, colors: [
                                "Middle.Group 1.Fill 1": iconColor,
                                "Top.Group 1.Fill 1": iconColor,
                                "Bottom.Group 1.Fill 1": iconColor,
                                "EXAMPLE.Group 1.Fill 1": iconColor,
                                "Line.Group 1.Stroke 1": iconColor
                            ], title: nil, text: "You will no longer receive a notification when **\(peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder))** posts a story.", customUndoText: nil, timeout: nil),
                            elevatedLayout: false,
                            animateInAsReplacement: false,
                            action: { _ in return false }
                        ), in: .current)
                    }
                }
            })))
            
            items.append(.action(ContextMenuActionItem(text: "Move to chats", icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/MoveToChats"), color: theme.contextMenu.primaryColor)
            }, action: { _, f in
                f(.default)

                context.engine.peers.updatePeerStoriesHidden(id: peerId, isHidden: false)
                
                guard let parentController = contactsController?.parent as? TabBarController, let chatsController = (contactsController?.navigationController as? TelegramRootControllerInterface)?.getChatsController(), let sourceFrame = parentController.frameForControllerTab(controller: chatsController) else {
                    return
                }
                
                if let peer {
                    let location = CGRect(origin: CGPoint(x: sourceFrame.midX, y: sourceFrame.minY + 1.0), size: CGSize())
                    let tooltipController = TooltipScreen(
                        context: context,
                        account: context.account,
                        sharedContext: context.sharedContext,
                        text: .markdown(text: "Stories from \(peer.compactDisplayTitle) will now be shown in Chats, not Contacts."),
                        icon: .peer(peer: peer, isStory: true),
                        action: TooltipScreen.Action(
                            title: "Undo",
                            action: {
                                context.engine.peers.updatePeerStoriesHidden(id: peer.id, isHidden: true)
                            }
                        ),
                        location: .point(location, .bottom),
                        shouldDismissOnTouch: { _ in return .dismiss(consume: false) }
                    )
                    contactsController?.present(tooltipController, in: .window(.root))
                }
            })))
            
            return items
        }
        
        items.append(.action(ContextMenuActionItem(text: strings.ContactList_Context_SendMessage, icon: { theme in generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Message"), color: theme.contextMenu.primaryColor) }, action: { _, f in
            let _ = (context.engine.data.get(
                TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)
            )
            |> deliverOnMainQueue).start(next: { peer in
                guard let peer = peer else {
                    return
                }
                if let contactsController = contactsController, let navigationController = contactsController.navigationController as? NavigationController {
                    context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), peekData: nil))
                }
                f(.default)
            })
        })))
        
        var canStartSecretChat = true
        if case let .user(user) = peer, user.flags.contains(.isSupport) {
            canStartSecretChat = false
        }
        
        if canStartSecretChat {
            items.append(.action(ContextMenuActionItem(text: strings.ContactList_Context_StartSecretChat, icon: { theme in generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Timer"), color: theme.contextMenu.primaryColor) }, action: { _, f in
                let _ = (context.engine.peers.mostRecentSecretChat(id: peerId)
                |> deliverOnMainQueue).start(next: { currentPeerId in
                    if let currentPeerId = currentPeerId {
                        let _ = (context.engine.data.get(
                            TelegramEngine.EngineData.Item.Peer.Peer(id: currentPeerId)
                        )
                        |> deliverOnMainQueue).start(next: { peer in
                            guard let peer = peer else {
                                return
                            }
                            
                            if let contactsController = contactsController, let navigationController = (contactsController.navigationController as? NavigationController) {
                                context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), peekData: nil))
                            }
                        })
                    } else {
                        var createSignal = context.engine.peers.createSecretChat(peerId: peerId)
                        var cancelImpl: (() -> Void)?
                        let progressSignal = Signal<Never, NoError> { subscriber in
                            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                            let controller = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: {
                                cancelImpl?()
                            }))
                            contactsController?.present(controller, in: .window(.root))
                            return ActionDisposable { [weak controller] in
                                Queue.mainQueue().async() {
                                    controller?.dismiss()
                                }
                            }
                        }
                        |> runOn(Queue.mainQueue())
                        |> delay(0.15, queue: Queue.mainQueue())
                        let progressDisposable = progressSignal.start()
                        
                        createSignal = createSignal
                        |> afterDisposed {
                            Queue.mainQueue().async {
                                progressDisposable.dispose()
                            }
                        }
                        let createSecretChatDisposable = MetaDisposable()
                        cancelImpl = {
                            createSecretChatDisposable.set(nil)
                        }
                        
                        createSecretChatDisposable.set((createSignal
                        |> deliverOnMainQueue).start(next: { peerId in
                            let _ = (context.engine.data.get(
                                TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)
                            )
                            |> deliverOnMainQueue).start(next: { peer in
                                guard let peer = peer else {
                                    return
                                }
                                
                                if let navigationController = (contactsController?.navigationController as? NavigationController) {
                                    context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), peekData: nil))
                                }
                            })
                        }, error: { error in
                            if let contactsController = contactsController {
                                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                                let text: String
                                switch error {
                                    case .limitExceeded:
                                        text = presentationData.strings.TwoStepAuth_FloodError
                                    default:
                                        text = presentationData.strings.Login_UnknownError
                                }
                                contactsController.present(textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
                            }
                        }))
                    }
                })
                f(.default)
            })))
        }
        
        var canCall = true
        if case let .user(user) = peer, (user.flags.contains(.isSupport) || !areVoiceCallsAvailable) {
            canCall = false
        }
        var canVideoCall = false
        if canCall {
            if areVideoCallsAvailable {
                canVideoCall = true
            }
        }
        
        if canCall {
            items.append(.action(ContextMenuActionItem(text: strings.ContactList_Context_Call, icon: { theme in
                generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Call"), color: theme.contextMenu.primaryColor)
            }, action: { _, f in
                context.requestCall(peerId: peerId, isVideo: false, completion: {})
                f(.default)
            })))
        }
        if canVideoCall {
            items.append(.action(ContextMenuActionItem(text: strings.ContactList_Context_VideoCall, icon: { theme in generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/VideoCall"), color: theme.contextMenu.primaryColor)
            }, action: { _, f in
                context.requestCall(peerId: peerId, isVideo: true, completion: {})
                f(.default)
            })))
        }
        return items
    }
}

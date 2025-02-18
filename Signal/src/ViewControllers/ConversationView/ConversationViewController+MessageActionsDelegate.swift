//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

extension ConversationViewController: MessageActionsDelegate {
    func messageActionsShowDetailsForItem(_ itemViewModel: CVItemViewModelImpl) {
        showDetailView(itemViewModel)
    }

    func prepareDetailViewForInteractivePresentation(_ itemViewModel: CVItemViewModelImpl) {
        AssertIsOnMainThread()

        guard let message = itemViewModel.interaction as? TSMessage else {
            return owsFailDebug("Invalid interaction.")
        }

        guard let panHandler = panHandler else {
            return owsFailDebug("Missing panHandler")
        }

        let detailVC = MessageDetailViewController(message: message, thread: thread)
        detailVC.detailDelegate = self
        conversationSplitViewController?.navigationTransitionDelegate = detailVC
        panHandler.messageDetailViewController = detailVC
    }

    func showDetailView(_ itemViewModel: CVItemViewModelImpl) {
        AssertIsOnMainThread()

        guard let message = itemViewModel.interaction as? TSMessage else {
            owsFailDebug("Invalid interaction.")
            return
        }

        let panHandler = viewState.panHandler

        let detailVC: MessageDetailViewController
        if let panHandler = panHandler,
           let messageDetailViewController = panHandler.messageDetailViewController,
           messageDetailViewController.message.uniqueId == message.uniqueId {
            detailVC = messageDetailViewController
            detailVC.pushPercentDrivenTransition = panHandler.percentDrivenTransition
        } else {
            detailVC = MessageDetailViewController(message: message, thread: thread)
            detailVC.detailDelegate = self
            conversationSplitViewController?.navigationTransitionDelegate = detailVC
        }

        navigationController?.pushViewController(detailVC, animated: true)
    }

    func messageActionsReplyToItem(_ itemViewModel: CVItemViewModelImpl) {
        populateReplyForMessage(itemViewModel)
    }

    public func populateReplyForMessage(_ itemViewModel: CVItemViewModelImpl) {
        AssertIsOnMainThread()

        if DebugFlags.internalLogging {
            Logger.info("")
        }
        guard let inputToolbar = inputToolbar else {
            owsFailDebug("Missing inputToolbar.")
            return
        }

        self.uiMode = .normal

        let load = {
            Self.databaseStorage.read { transaction in
                OWSQuotedReplyModel.quotedReplyForSending(withItem: itemViewModel, transaction: transaction)
            }
        }
        guard let quotedReply = load() else {
            owsFailDebug("Could not build quoted reply.")
            return
        }

        inputToolbar.quotedReply = quotedReply
        inputToolbar.beginEditingMessage()
    }

    func messageActionsForwardItem(_ itemViewModel: CVItemViewModelImpl) {
        AssertIsOnMainThread()

        ForwardMessageViewController.present(forItemViewModels: [itemViewModel],
                                             from: self,
                                             delegate: self)
    }

    func messageActionsStartedSelect(initialItem itemViewModel: CVItemViewModelImpl) {
        uiMode = .selection

        selectionState.add(itemViewModel: itemViewModel, selectionType: .allContent)
    }

    func messageActionsDeleteItem(_ itemViewModel: CVItemViewModelImpl) {
        let actionSheetController = ActionSheetController(message: NSLocalizedString(
            "MESSAGE_ACTION_DELETE_FOR_TITLE",
            comment: "The title for the action sheet asking who the user wants to delete the message for."
        ))

        let deleteForMeAction = ActionSheetAction(
            title: CommonStrings.deleteForMeButton,
            style: .destructive
        ) { _ in
            itemViewModel.deleteAction()
        }
        actionSheetController.addAction(deleteForMeAction)

        if canBeRemotelyDeleted(item: itemViewModel),
           let message = itemViewModel.interaction as? TSOutgoingMessage {

            let deleteForEveryoneAction = ActionSheetAction(
                title: NSLocalizedString(
                    "MESSAGE_ACTION_DELETE_FOR_EVERYONE",
                    comment: "The title for the action that deletes a message for all users in the conversation."
                ),
                style: .destructive
            ) { [weak self] _ in
                self?.showDeleteForEveryoneConfirmationIfNecessary {
                    guard let self = self else { return }

                    let deleteMessage = TSOutgoingDeleteMessage(thread: self.thread, message: message)

                    self.databaseStorage.write { transaction in
                        // Reset the sending states, so we can render the sending state of the deleted message.
                        // TSOutgoingDeleteMessage will automatically pass through it's send state to the message
                        // record that it is deleting.
                        message.updateWith(recipientAddressStates: deleteMessage.recipientAddressStates, transaction: transaction)
                        message.updateWithRemotelyDeletedAndRemoveRenderableContent(with: transaction)
                        Self.messageSenderJobQueue.add(message: deleteMessage.asPreparer, transaction: transaction)
                    }
                }
            }
            actionSheetController.addAction(deleteForEveryoneAction)
        }

        actionSheetController.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheetController)
    }
}

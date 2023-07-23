//
//  AddSummaryViewModel.swift
//  ALog
//
//  Created by Xin Du on 2023/07/21.
//

import Foundation
import CoreData
import XLog

class AddSummaryViewModel: ObservableObject {
    let item: SummaryItem
    let moc: NSManagedObjectContext
    
    @Published var defaultTitle = ""
    @Published var dayId = 0
    
    @Published var selectedPrompt: PromptEntity?
    @Published var promptToEdit: PromptEntity?
    @Published var showAddPrompt: Bool = false
    
    @Published var fatalErrorMessage = "" {
        didSet {
            showFatalError = true
        }
    }
    @Published var showFatalError = false
    @Published var memoContent = ""
    @Published var summaryMessage = ""
    
    @Published var navPath: [AddSummaryNavPath] = []
    
    @Published var isSummarizing = false
    @Published var summarizedResponse = ""
    @Published var summaryError = ""
    @Published var saved = false
    
    private var cancellationTask: Task<Void, Never>? = nil
    
    init(item: SummaryItem, moc: NSManagedObjectContext) {
        self.item = item
        self.moc = moc
        
        if case let .day(id) = item {
            dayId = id
        }
        
        self.defaultTitle = L(.sum_title_default, DateHelper.formatIdentifier(dayId, dateFormat: "yyyy-MM-dd"))
    }
    
    func fetchEntries() {
        let fetchRequest = MemoEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "day = %d", dayId)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \MemoEntity.createdAt, ascending: true)]
        var ret = ""
        do {
            let memos = try moc.fetch(fetchRequest).filter { !$0.viewContent.isEmpty }
            for memo in memos {
                ret.append("\n[\(memo.viewTime)] \(memo.viewContent)\n")
            }
            
            if ret.count < Constants.Summary.lengthLimit {
                fatalErrorMessage = L(.sum_text_too_short)
            } else {
                memoContent = ret
            }
        } catch {
            XLog.error(error, source: "Sumary")
        }
    }
    
    func generateMessage() {
        guard let prompt = selectedPrompt else { return }
        var ret = prompt.viewContent
        ret.append("\n\n------")
        ret.append(memoContent)
        ret.append("------\n")
        summaryMessage = ret
    }
    
    func summarize() {
        if isSummarizing { return }
        cancellationTask = Task { @MainActor in
            isSummarizing = true
            do {
                summaryError = ""
                summarizedResponse = ""
                let stream = try await OpenAIClient().summarize(summaryMessage)
                for try await text in stream {
                    summarizedResponse += text
                }
            } catch {
                summaryError = ErrorHelper.desc(error)
                XLog.error(error, source: "Summary")
            }
            isSummarizing = false
        }
    }
    
    func save() {
        let summary = SummaryEntity.newEntity(moc: moc)
        summary.content = summarizedResponse
        summary.title = defaultTitle
        
        do {
            try moc.save()
            saved = true
        } catch {
            XLog.error(error, source: "Summary")
        }
    }
    
    func cancelTasks() {
        cancellationTask?.cancel()
    }
}

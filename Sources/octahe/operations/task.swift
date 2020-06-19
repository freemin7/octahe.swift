//
//  task.swift
//  
//
//  Created by Kevin Carter on 6/19/20.
//

import Foundation


enum TaskStates {
    case new, running, success, degraded, failed
}


var taskRecords: [Int: TaskRecord] = [:]


class TaskRecord {
    let task: String
    let taskItem: typeDeploy
    var state = TaskStates.new

    init(task: String, taskItem: typeDeploy) {
        self.task = task
        self.taskItem = taskItem
    }
}


class TaskOperations {
    lazy var tasksInProgress: [IndexPath: Operation] = [:]
    lazy var taskQueue: OperationQueue = {
    var queue = OperationQueue()
        queue.name = "Task queue"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
}


class TaskOperation: Operation {
    let taskRecord: TaskRecord
    let deployItem: (key: String, value: typeDeploy)
    let steps: Int
    let stepIndex: Int
    let args: ConfigParse
    let options: octaheCLI.Options
    var printStatus: Bool = true

    init(deployItem: (key: String, value: typeDeploy), steps: Int, stepIndex: Int,
         args: ConfigParse, options: octaheCLI.Options) {
        self.deployItem = deployItem
        self.steps = steps
        self.stepIndex = stepIndex
        self.args = args
        self.options = options
        if let taskRecordsLookup = taskRecords[stepIndex] {
            self.taskRecord = taskRecordsLookup
        } else {
            let taskRecordsLookup = TaskRecord(task: deployItem.key, taskItem: deployItem.value)
            taskRecords[stepIndex] = taskRecordsLookup
            self.taskRecord = taskRecords[stepIndex]!
        }
    }

    override func main() {
        let availableTargets = targetRecords.values.filter{$0.state == .available}
        if availableTargets.count == 0 && targetRecords.keys.count > 0 {
            return
        }
        let targetQueue = TargetOperations(connectionQuota: options.connectionQuota)
        let statusLine = String(format: "Step \(stepIndex)/\(steps) : \(deployItem.key) \(deployItem.value.original)")
        for target in args.octaheTargets {
            if let targetData = args.octaheTargetHash[target] {
                let targetOperation = TargetOperation(
                    target: targetData,
                    args: args,
                    options: options,
                    taskIndex: stepIndex
                )
                if targetRecords[target]?.state == .available {
                    if printStatus {
                        print(statusLine)
                        printStatus = false
                    }
                    targetQueue.nodeQueue.addOperation(targetOperation)
                }
            }
        }
        targetQueue.nodeQueue.waitUntilAllOperationsAreFinished()
        let degradedTargetStates = targetRecords.values.filter{$0.state == .failed}
        if degradedTargetStates.count == args.octaheTargets.count {
            print(" --> Failed")
            self.taskRecord.state = .failed
        } else if degradedTargetStates.count > 0 {
            print(" --> Degraded")
        } else {
            print(" --> Done")
        }
    }
}
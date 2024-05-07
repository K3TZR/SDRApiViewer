//
//  MessagesModel.swift
//  SDRApiViewer
//
//  Created by Douglas Adams on 1/28/24.
//

import ComposableArchitecture
import Foundation
import SwiftUI

import SharedFeature
import TcpFeature
import XCGLogFeature

@Observable
public final class MessagesModel {
  // ----------------------------------------------------------------------------
  // MARK: - Singleton
  
  public static var shared = MessagesModel()
  private init() {}
  
  // ----------------------------------------------------------------------------
  // MARK: - Public properties
  
  public var filteredMessages = IdentifiedArrayOf<TcpMessage>()

  // ----------------------------------------------------------------------------
  // MARK: - Private properties
  
  private var _filter: MessageFilter = .all
  private var _filterText = ""
  private var _messages = IdentifiedArrayOf<TcpMessage>()
  private var _showPings = false
  private var _tcpMessageSubscription: Task<(), Never>?
  
  // ----------------------------------------------------------------------------
  // MARK: - Public methods
  
  public func start(_ clearOnStart: Bool) {
    if clearOnStart { clearAll() }
    subscribeToTcpMessages()
  }

  public func stop(_ clearOnStop: Bool) {
    _tcpMessageSubscription = nil
    if clearOnStop { clearAll() }
  }

  /// Clear all messages
  public func clearAll(_ enabled: Bool = true) {
    if enabled {
      self._messages.removeAll()
      removeAllFilteredMessages()
    }
  }

  /// Set the messages filter parameters and re-filter
  public func reFilter(_ filter: MessageFilter, _ filterText: String) {
    _filter = filter
    _filterText = filterText
    reFilterMessages()
  }

  /// Set the messages filter parameters and re-filter
//  public func reFilter(filterText: String) {
//    _filterText = filterText
//    reFilterMessages()
//  }

  // ----------------------------------------------------------------------------
  // MARK: - Private filter methods
  
  /// Rebuild the entire filteredMessages array
  private func reFilterMessages() {
    var _filteredMessages = IdentifiedArrayOf<TcpMessage>()
    
    // re-filter the entire messages array
    switch (_filter, _filterText) {

    case (MessageFilter.all, _):        _filteredMessages = _messages
    case (MessageFilter.prefix, ""):    _filteredMessages = _messages
    case (MessageFilter.prefix, _):     _filteredMessages = _messages.filter { $0.text.localizedCaseInsensitiveContains("|" + _filterText) }
    case (MessageFilter.includes, _):   _filteredMessages = _messages.filter { $0.text.localizedCaseInsensitiveContains(_filterText) }
    case (MessageFilter.excludes, ""):  _filteredMessages = _messages
    case (MessageFilter.excludes, _):   _filteredMessages = _messages.filter { !$0.text.localizedCaseInsensitiveContains(_filterText) }
    case (MessageFilter.command, _):    _filteredMessages = _messages.filter { $0.text.prefix(1) == "C" }
    case (MessageFilter.S0, _):         _filteredMessages = _messages.filter { $0.text.prefix(3) == "S0|" }
    case (MessageFilter.status, _):     _filteredMessages = _messages.filter { $0.text.prefix(1) == "S" && $0.text.prefix(3) != "S0|"}
    case (MessageFilter.reply, _):      _filteredMessages = _messages.filter { $0.text.prefix(1) == "R" }
    }
    
    Task { [_filteredMessages] in
      await MainActor.run { filteredMessages = _filteredMessages }
    }
  }
  
  private func removeAllFilteredMessages() {
    Task { 
      await MainActor.run { filteredMessages = IdentifiedArrayOf<TcpMessage>() }
    }
  }

  // ----------------------------------------------------------------------------
  // MARK: - Private message processing methods
  
  private func subscribeToTcpMessages()  {
    _tcpMessageSubscription = Task(priority: .high) {
      log("MessagesModel: TcpMessage subscription STARTED", .debug, #function, #file, #line)
      for await msg in Tcp.shared.testerStream {
        process(msg)
      }
      log("MessagesModel: : TcpMessage subscription STOPPED", .debug, #function, #file, #line)
    }
  }
  
  /// Process a TcpMessage
  /// - Parameter msg: a TcpMessage struct
  private func process(_ msg: TcpMessage) {

    // ignore routine replies (i.e. replies with no error or no attached data)
    func ignoreReply(_ text: String) -> Bool {
      if text.first != "R" { return false }     // not a Reply
      let parts = text.components(separatedBy: "|")
      if parts.count < 3 { return false }       // incomplete
      if parts[1] != kNoError { return false }  // error of some type
      if parts[2] != "" { return false }        // additional data present
      return true                               // otherwise, ignore it
    }

    // ignore received replies unless they are non-zero or contain additional data
    if msg.direction == .received && ignoreReply(msg.text) { return }
    // ignore sent "ping" messages unless showPings is true
    if msg.text.contains("ping") && _showPings == false { return }
    // add it to the backing collection
    _messages.append(msg)
    
    Task {
      await MainActor.run {
        // add it to the published collection (if appropriate)
        switch (_filter, _filterText) {

        case (MessageFilter.all, _):        filteredMessages.append(msg)
        case (MessageFilter.prefix, ""):    filteredMessages.append(msg)
        case (MessageFilter.prefix, _):     if msg.text.localizedCaseInsensitiveContains("|" + _filterText) { filteredMessages.append(msg) }
        case (MessageFilter.includes, _):   if msg.text.localizedCaseInsensitiveContains(_filterText) { filteredMessages.append(msg) }
        case (MessageFilter.excludes, ""):  filteredMessages.append(msg)
        case (MessageFilter.excludes, _):   if !msg.text.localizedCaseInsensitiveContains(_filterText) { filteredMessages.append(msg) }
        case (MessageFilter.command, _):    if msg.text.prefix(1) == "C" { filteredMessages.append(msg) }
        case (MessageFilter.S0, _):         if msg.text.prefix(3) == "S0|" { filteredMessages.append(msg) }
        case (MessageFilter.status, _):     if msg.text.prefix(1) == "S" && msg.text.prefix(3) != "S0|" { filteredMessages.append(msg) }
        case (MessageFilter.reply, _):      if msg.text.prefix(1) == "R" { filteredMessages.append(msg) }
        }
      }
    }
  }
}

// Which focused fields count as a message box Appshots may paste into.
import Foundation

func check(_ ok: Bool, _ what: String) {
    if !ok { print("FAIL: \(what)"); exit(1) }
}

let main = "AXStandardWindow"
check(Paster.isPromptLabel("Prompt", windowSubrole: main), "Code tab message box")
check(Paster.isPromptLabel("Prompt", windowSubrole: nil), "Code tab box when the window kind is unknown")
check(Paster.isPromptLabel("Write your reply to Claude", windowSubrole: main), "chat or project thread composer")
check(Paster.isPromptLabel("Write your prompt to Claude", windowSubrole: main), "new chat composer")
check(!Paster.isPromptLabel("Write your prompt to Claude", windowSubrole: "AXFloatingWindow"), "Quick Entry panel")
check(!Paster.isPromptLabel("Write your reply to Claude", windowSubrole: nil), "chat composer in an unknown window")
check(!Paster.isPromptLabel("Message 12", windowSubrole: main), "a message in the conversation")
check(!Paster.isPromptLabel(nil, windowSubrole: main), "no label")
print("paster ok")

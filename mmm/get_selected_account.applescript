on run
	tell application "Mail"
		set selectedMessages to selection

		if selectedMessages is {} then
			beep
			return ""
		end if

		set selectedAccountID to id of account of mailbox of item 1 of selectedMessages

		repeat with selectedMessage in selectedMessages
			set currentAccountID to id of account of mailbox of selectedMessage

			if currentAccountID is not selectedAccountID then
				beep
				return ""
			end if
		end repeat

		return selectedAccountID
	end tell
end run

on run argv
	if (count of argv) = 0 then
		beep
		return
	end if
	
	set destinationPath to item 1 of argv
	
	set oldDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to " / "
	set mailboxNames to text items of destinationPath
	set AppleScript's text item delimiters to oldDelimiters
	
	tell application "Mail"
		set selectedMessages to selected messages of first message viewer
		
		if selectedMessages is {} then
			beep
			return
		end if
		

		-- All selected messages were already validated as belonging to
		-- the same account when the Script Filter was populated.
		set selectedAccount to account of mailbox of item 1 of selectedMessages
		
		-- Start at the account and descend through the logical mailbox path.
		set destinationMailbox to selectedAccount
		
		repeat with mailboxName in mailboxNames
			set destinationMailbox to mailbox (mailboxName as text) of destinationMailbox
		end repeat

        log selectedMessages
		
		move selectedMessages to destinationMailbox
	end tell
end run

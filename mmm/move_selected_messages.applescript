-- Capture direct menu items and names with one Accessibility request per property
on menuSnapshot(menuObject)
	tell application "System Events"
		-- Preserve direct item references for later submenu traversal or clicking
		set directItems to every menu item of menuObject
		-- Fetch all names together to avoid one cross-process request per item
		set directNames to name of every menu item of menuObject
	end tell

	return {menuItems:directItems, menuNames:directNames}
end menuSnapshot

-- Return list indexes whose cached menu name matches the requested name
on indexesNamed(menuNames, requestedName, firstIndex, lastIndex)
	-- Collect every match so duplicate destinations can be rejected safely
	set matchingIndexes to {}

	if firstIndex > lastIndex then return matchingIndexes

	-- Compare cached names without making additional Accessibility requests
	repeat with itemIndex from firstIndex to lastIndex
		-- Coerce AppleScript list references before comparing text values
		set candidateName to item itemIndex of menuNames as text
		if candidateName is requestedName then set end of matchingIndexes to itemIndex
	end repeat

	return matchingIndexes
end indexesNamed

-- Return an item's attached submenu after Mail has populated its dynamic contents
on submenuFor(menuItemObject)
	tell application "System Events"
		-- A real submenu is exposed as a child menu even before its dynamic items appear
		try
			set attachedMenu to first menu of menuItemObject
		on error
			return missing value
		end try

		-- Ask Mail to display the known submenu without probing non-submenu headings
		try
			perform action "AXShowMenu" of menuItemObject
		on error errorMessage
			error "Could not open a Mail submenu: " & errorMessage
		end try

		-- Retry briefly because Mail populates Move to submenus lazily
		repeat with attemptNumber from 1 to 10
			try
				if (count of menu items of attachedMenu) > 0 then return attachedMenu
			end try

			delay 0.05
		end repeat
	end tell

	return missing value
end submenuFor

-- Resolve a logical mailbox path beneath a known menu
on itemForMailboxPath(rootMenu, mailboxPath)
	-- Start traversal at the menu associated with the selected account
	set currentMenu to rootMenu
	-- Retain the final unique item for the eventual native Mail click
	set resolvedItem to missing value

	-- Resolve one mailbox component at each submenu level
	repeat with pathIndex from 1 to count of mailboxPath
		-- Convert the current logical path component to plain text
		set pathComponent to item pathIndex of mailboxPath as text
		-- Snapshot this level once instead of querying each item individually
		set currentSnapshot to my menuSnapshot(currentMenu)
		-- Separate cached item references from their cached Accessibility names
		set currentItems to menuItems of currentSnapshot
		set currentNames to menuNames of currentSnapshot
		-- Require a single same-level match before following or clicking it
		set matchingIndexes to my indexesNamed(currentNames, pathComponent, 1, count of currentNames)

		if (count of matchingIndexes) is not 1 then return missing value

		-- Resolve the unique matching item through its cached list index
		set resolvedItem to item (item 1 of matchingIndexes) of currentItems

		if pathIndex < count of mailboxPath then
			-- Open only the submenu on the matched logical path
			set currentMenu to my submenuFor(resolvedItem)
			if currentMenu is missing value then return missing value
		end if
	end repeat

	return resolvedItem
end itemForMailboxPath

-- Report whether a cached menu name is one of Mail's displayed account names
on listContains(textValues, requestedValue)
	-- Compare exact display names so account section boundaries stay deterministic
	repeat with textValue in textValues
		if (textValue as text) is requestedValue then return true
	end repeat

	return false
end listContains

-- Find the end of a flattened account section in the cached top-level names
on flattenedSectionEnd(menuNames, allAccountNames, sectionStart)
	-- Default the section boundary to the final top-level Move to item
	set sectionEnd to count of menuNames

	-- The next displayed account heading begins a different account's section
	repeat with itemIndex from sectionStart to count of menuNames
		-- Read the candidate from cached Accessibility names
		set candidateName to item itemIndex of menuNames as text
		if my listContains(allAccountNames, candidateName) then
			set sectionEnd to itemIndex - 1
			exit repeat
		end if
	end repeat

	return sectionEnd
end flattenedSectionEnd

-- Resolve a logical mailbox path from a flattened top-level account section
on itemInFlattenedSection(moveToItems, moveToNames, accountIndex, allAccountNames, mailboxPath)
	-- A flattened section begins immediately after its named account heading
	set sectionStart to accountIndex + 1
	-- Stop before the next account heading to prevent cross-account matches
	set sectionEnd to my flattenedSectionEnd(moveToNames, allAccountNames, sectionStart)
	-- Match the first logical component only inside the selected account section
	set firstComponent to item 1 of mailboxPath as text
	-- Preserve all section matches so duplicated names cause a safe failure
	set matchingIndexes to my indexesNamed(moveToNames, firstComponent, sectionStart, sectionEnd)

	if (count of matchingIndexes) is not 1 then return missing value

	-- Select the unique top-level mailbox by its cached index
	set resolvedItem to item (item 1 of matchingIndexes) of moveToItems
	if (count of mailboxPath) is 1 then return resolvedItem

	-- Descend only when the logical destination has additional components
	set childMenu to my submenuFor(resolvedItem)
	if childMenu is missing value then return missing value
	-- Remove the top-level component already resolved in the flattened section
	set remainingPath to items 2 thru -1 of mailboxPath

	return my itemForMailboxPath(childMenu, remainingPath)
end itemInFlattenedSection

-- Format a logical mailbox path for actionable error messages
on joinedMailboxPath(mailboxPath)
	-- Preserve the process-wide delimiter setting while joining components
	set oldDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to " / "
	set pathText to mailboxPath as text
	set AppleScript's text item delimiters to oldDelimiters

	return pathText
end joinedMailboxPath

-- Open Mail's native Move to menu and click the unique account-scoped destination
on moveSelectionThroughMenu(accountName, allAccountNames, mailboxPath)
	-- Gmail ignores Mail's AppleScript move command from All Mail; the native UI applies Gmail label semantics correctly
	tell application "Mail" to activate
	delay 0.1

	tell application "System Events"
		if UI elements enabled is false then error "UI scripting is disabled; allow Accessibility access for the app running this workflow"

		-- Address named menus so minor macOS menu reordering does not affect lookup
		tell process "Mail"
			set frontmost to true
			-- Resolve Mail's Message menu by its Accessibility name
			set messageMenuItem to menu bar item "Message" of menu bar 1
			click messageMenuItem
			-- Retain the opened Message menu for its named Move to lookup
			set messageMenu to menu "Message" of messageMenuItem
			-- Require a unique named Move to item without using a numeric position
			set moveToItems to every menu item of messageMenu whose name is "Move to"

			if (count of moveToItems) is not 1 then error "Could not uniquely locate Message > Move to in Mail"

			-- Preserve the unique Move to menu item for dynamic submenu opening
			set moveToItem to item 1 of moveToItems
		end tell
	end tell

	-- Open the dynamic Move to submenu before taking a single top-level snapshot
	set moveToMenu to my submenuFor(moveToItem)
	if moveToMenu is missing value then error "Mail did not populate Message > Move to"
	-- Cache direct Move to items and names instead of recursively requesting entire contents
	set moveToSnapshot to my menuSnapshot(moveToMenu)
	-- Separate top-level item references from their cached names
	set moveToDirectItems to menuItems of moveToSnapshot
	set moveToDirectNames to menuNames of moveToSnapshot
	-- Associate the destination with one unique top-level account heading
	set accountIndexes to my indexesNamed(moveToDirectNames, accountName, 1, count of moveToDirectNames)

	if (count of accountIndexes) is 0 then error "Could not locate account \"" & accountName & "\" in Message > Move to"
	if (count of accountIndexes) > 1 then error "More than one account heading named \"" & accountName & "\" appears in Message > Move to"

	-- Resolve the unique account heading through its cached top-level index
	set accountIndex to item 1 of accountIndexes
	set accountItem to item accountIndex of moveToDirectItems
	-- Prefer an attached account submenu when Mail exposes the nested layout
	set accountMenu to my submenuFor(accountItem)
	-- Keep the final destination item separate until one layout resolves uniquely
	set destinationItem to missing value

	if accountMenu is not missing value then
		-- Search only inside the selected account submenu
		set destinationItem to my itemForMailboxPath(accountMenu, mailboxPath)
	else
		-- Search only the cached top-level section belonging to the selected account
		set destinationItem to my itemInFlattenedSection(moveToDirectItems, moveToDirectNames, accountIndex, allAccountNames, mailboxPath)
	end if

	if destinationItem is missing value then error "Could not uniquely locate account \"" & accountName & "\" and mailbox \"" & my joinedMailboxPath(mailboxPath) & "\" in Message > Move to"

	tell application "System Events"
		if enabled of destinationItem is false then error "The Move to destination \"" & my joinedMailboxPath(mailboxPath) & "\" is disabled"
		-- AXPick invokes the unique mailbox command discovered through Accessibility
		perform action "AXPick" of destinationItem
	end tell
end moveSelectionThroughMenu

on run argv
	if (count of argv) = 0 then
		beep
		return
	end if

	-- Alfred supplies the destination as a slash-separated logical mailbox path
	set destinationPath to item 1 of argv
	-- Preserve the process-wide delimiter setting while parsing the path
	set oldDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to " / "
	-- Split the requested logical path into mailbox hierarchy components
	set mailboxNames to text items of destinationPath
	set AppleScript's text item delimiters to oldDelimiters

	tell application "Mail"
		-- Keep the existing Mail selection semantics so the UI command acts on the same messages
		set selectedMessages to selected messages of first message viewer

		if selectedMessages is {} then
			beep
			return
		end if

		-- The Script Filter already validates that every selected message belongs to this account
		set selectedAccount to account of mailbox of item 1 of selectedMessages
		-- Use Mail's displayed account name to scope duplicate mailbox names correctly
		set selectedAccountName to name of selectedAccount
		-- Gather displayed account names to recognize flattened section boundaries
		set allAccountNames to name of every account
		-- Preserve the original mailbox traversal as validation of the requested path
		set destinationMailbox to selectedAccount

		-- Resolve every component before opening UI menus so invalid paths fail without a click
		repeat with mailboxName in mailboxNames
			set destinationMailbox to mailbox (mailboxName as text) of destinationMailbox
		end repeat
	end tell

	my moveSelectionThroughMenu(selectedAccountName, allAccountNames, mailboxNames)
end run

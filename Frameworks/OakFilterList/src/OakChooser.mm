#import "OakChooser.h"
#import "ui/TableView.h"
#import "ui/SearchField.h"
#import <OakAppKit/OakAppKit.h>
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <OakFoundation/OakFoundation.h>
#import <OakFoundation/NSString Additions.h>
#import <ns/ns.h>
#import <text/ranker.h>

NSMutableAttributedString* CreateAttributedStringWithMarkedUpRanges (std::string const& in, std::vector< std::pair<size_t, size_t> > const& ranges, size_t offset)
{
	NSMutableParagraphStyle* paragraphStyle = [[NSMutableParagraphStyle alloc] init];
	[paragraphStyle setLineBreakMode:NSLineBreakByTruncatingMiddle];

	NSDictionary* baseAttributes      = @{ NSParagraphStyleAttributeName : paragraphStyle };
	NSDictionary* highlightAttributes = @{ NSParagraphStyleAttributeName : paragraphStyle, NSUnderlineStyleAttributeName : @1 };

	NSMutableAttributedString* res = [[NSMutableAttributedString alloc] init];

	size_t from = 0;
	for(auto range : ranges)
	{
		[res appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithCxxString:std::string(in.begin() + from, in.begin() + range.first + offset)] attributes:baseAttributes]];
		[res appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithCxxString:std::string(in.begin() + range.first + offset, in.begin() + range.second + offset)] attributes:highlightAttributes]];
		from = range.second + offset;
	}
	if(from < in.size())
		[res appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithCxxString:in.substr(from)] attributes:baseAttributes]];

	return res;
}

@interface OakChooser () <NSWindowDelegate, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate>
@end

static void* kFirstResponderBinding = &kFirstResponderBinding;

@implementation OakChooser
- (id)init
{
	if((self = [super init]))
	{
		_items = @[ ];

		_searchField = [[OakLinkedSearchField alloc] initWithFrame:NSZeroRect];
		[_searchField.cell setScrollable:YES];
		[_searchField.cell setSendsSearchStringImmediately:YES];
		if(![NSApp isFullKeyboardAccessEnabled])
			_searchField.focusRingType = NSFocusRingTypeNone;
		_searchField.delegate = self;

		NSTableColumn* tableColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
		tableColumn.dataCell = [[NSTextFieldCell alloc] initTextCell:@""];
		[tableColumn.dataCell setLineBreakMode:NSLineBreakByTruncatingMiddle];

		OakInactiveTableView* tableView = [[OakInactiveTableView alloc] initWithFrame:NSZeroRect];
		[tableView addTableColumn:tableColumn];
		tableView.headerView              = nil;
		tableView.focusRingType           = NSFocusRingTypeNone;
		tableView.allowsEmptySelection    = NO;
		tableView.allowsMultipleSelection = NO;
		tableView.refusesFirstResponder   = YES;
		tableView.doubleAction            = @selector(accept:);
		tableView.target                  = self;
		tableView.dataSource              = self;
		tableView.delegate                = self;
		if(nil != &NSAccessibilitySharedFocusElementsAttribute)
			[_searchField.cell accessibilitySetOverrideValue:@[tableView] forAttribute:NSAccessibilitySharedFocusElementsAttribute];
		_tableView = tableView;

		_scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
		_scrollView.hasVerticalScroller   = YES;
		_scrollView.hasHorizontalScroller = NO;
		_scrollView.autohidesScrollers    = YES;
		_scrollView.borderType            = NSNoBorder;
		_scrollView.documentView          = _tableView;

		_statusTextField = [[NSTextField alloc] initWithFrame:NSZeroRect];
		_statusTextField.bezeled         = NO;
		_statusTextField.bordered        = NO;
		_statusTextField.drawsBackground = NO;
		_statusTextField.editable        = NO;
		_statusTextField.font            = OakStatusBarFont();
		_statusTextField.selectable      = NO;
		[[_statusTextField cell] setBackgroundStyle:NSBackgroundStyleRaised];
		[[_statusTextField cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
		[_statusTextField setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
		[_statusTextField setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

		_itemCountTextField = [[NSTextField alloc] initWithFrame:NSZeroRect];
		_itemCountTextField.bezeled         = NO;
		_itemCountTextField.bordered        = NO;
		_itemCountTextField.drawsBackground = NO;
		_itemCountTextField.editable        = NO;
		_itemCountTextField.font            = OakStatusBarFont();
		_itemCountTextField.selectable      = NO;
		[[_itemCountTextField cell] setBackgroundStyle:NSBackgroundStyleRaised];
		[_itemCountTextField setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];

		_window = [[NSPanel alloc] initWithContentRect:NSMakeRect(600, 700, 400, 500) styleMask:(NSTitledWindowMask|NSClosableWindowMask|NSResizableWindowMask|NSTexturedBackgroundWindowMask) backing:NSBackingStoreBuffered defer:NO];
		[_window setAutorecalculatesContentBorderThickness:NO forEdge:NSMaxYEdge];
		[_window setAutorecalculatesContentBorderThickness:NO forEdge:NSMinYEdge];
		[_window setContentBorderThickness:32 forEdge:NSMaxYEdge];
		[_window setContentBorderThickness:23 forEdge:NSMinYEdge];
		[[_window standardWindowButton:NSWindowMiniaturizeButton] setHidden:YES];
		[[_window standardWindowButton:NSWindowZoomButton] setHidden:YES];
		_window.delegate           = self;
		_window.nextResponder      = self;
		_window.level              = NSFloatingWindowLevel;
		_window.releasedWhenClosed = NO;

		[_searchField bind:NSValueBinding toObject:self withKeyPath:@"filterString" options:nil];
		[_window addObserver:self forKeyPath:@"firstResponder" options:NSKeyValueObservingOptionOld|NSKeyValueObservingOptionNew context:kFirstResponderBinding];
	}
	return self;
}

- (void)dealloc
{
	_searchField.delegate = nil;
	[_searchField unbind:NSValueBinding];
	[_window removeObserver:self forKeyPath:@"firstResponder" context:kFirstResponderBinding];

	_window.delegate      = nil;
	_tableView.target     = nil;
	_tableView.dataSource = nil;
	_tableView.delegate   = nil;
}

- (void)showWindow:(id)sender
{
	[_window layoutIfNeeded];
	[_window recalculateKeyViewLoop];
	[_searchField.window makeFirstResponder:_searchField];
	[_window makeKeyAndOrderFront:self];
}

- (void)showWindowRelativeToFrame:(NSRect)parentFrame
{
	if(![_window isVisible])
	{
		[_window layoutIfNeeded];
		NSRect frame  = [_window frame];
		NSRect parent = parentFrame;

		frame.origin.x = NSMinX(parent) + round((NSWidth(parent)  - NSWidth(frame))  * 1 / 4);
		frame.origin.y = NSMinY(parent) + round((NSHeight(parent) - NSHeight(frame)) * 3 / 4);
		[_window setFrame:frame display:NO];
	}
	[self showWindow:self];
}

- (void)close
{
	[_window performClose:self];
}

// ===============================================================================
// = Set wether to render table view as active when search field gain/lose focus =
// ===============================================================================

- (void)setDrawTableViewAsHighlighted:(BOOL)flag
{
	[(OakInactiveTableView*)_tableView setDrawAsHighlighted:flag];
}

- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context
{
	if(context == kFirstResponderBinding)
	{
		BOOL oldIsSearchField = change[NSKeyValueChangeOldKey] == _searchField || change[NSKeyValueChangeOldKey] == _searchField.currentEditor;
		BOOL newIsSearchField = change[NSKeyValueChangeNewKey] == _searchField || change[NSKeyValueChangeNewKey] == _searchField.currentEditor;
		if(oldIsSearchField != newIsSearchField)
			self.drawTableViewAsHighlighted = newIsSearchField;
	}
}

// ======================================================
// = Forward Search Field Movement Actions to TableView =
// ======================================================

- (BOOL)control:(NSControl*)aControl textView:(NSTextView*)aTextView doCommandBySelector:(SEL)aCommand
{
	if(aCommand == @selector(deleteToBeginningOfLine:) && [aTextView.window tryToPerform:@selector(delete:) with:aTextView])
		return YES;

	NSUInteger res = OakPerformTableViewActionFromSelector(self.tableView, aCommand, aTextView);
	if(res == OakMoveAcceptReturn)
		[self performDefaultButtonClick:self];
	else if(res == OakMoveCancelReturn)
		[self cancel:self];
	return res != OakMoveNoActionReturn;
}

// ==============
// = Properties =
// ==============

- (void)setFilterString:(NSString*)aString
{
	if(_filterString == aString || [_filterString isEqualToString:aString])
		return;

	_filterString = [aString copy];
	_searchField.stringValue = aString ?: @"";

	if([_tableView numberOfRows] != 0)
	{
		[_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
		[_tableView scrollRowToVisible:0];
	}

	[self updateItems:self];

	// see http://lists.apple.com/archives/accessibility-dev/2014/Aug/msg00024.html
	if(nil != &NSAccessibilitySharedFocusElementsAttribute)
		NSAccessibilityPostNotification(_tableView, NSAccessibilitySelectedRowsChangedNotification);
}

- (void)setItems:(NSArray*)anArray
{
	_items = anArray;
	[_tableView reloadData];
	[_tableView scrollRowToVisible:_tableView.selectedRow == -1 ? 0 : _tableView.selectedRow];

	[self updateStatusText:self];

	_itemCountTextField.stringValue = [NSString stringWithFormat:@"%@ item%s", [NSNumberFormatter localizedStringFromNumber:@(_items.count) numberStyle:NSNumberFormatterDecimalStyle], _items.count == 1 ? "" : "s"];
}

- (NSArray*)selectedItems
{
	NSMutableArray* res = [NSMutableArray array];
	NSIndexSet* indexes = [_tableView selectedRowIndexes];
	for(NSUInteger i = [indexes firstIndex]; i != NSNotFound; i = [indexes indexGreaterThanIndex:i])
		[res addObject:_items[i]];
	return res;
}

// =================
// = Action Method =
// =================

- (void)performDefaultButtonClick:(id)sender
{
	if(self.window.defaultButtonCell)
			[self.window.defaultButtonCell performClick:sender];
	else	[self accept:sender];
}

- (void)accept:(id)sender
{
	[_window orderOut:self];
	if(_action)
		[NSApp sendAction:_action to:_target from:self];
	[_window close];
}

- (void)cancel:(id)sender
{
	[self close];
}

// =========================
// = NSTableViewDataSource =
// =========================

- (NSInteger)numberOfRowsInTableView:(NSTableView*)aTableView
{
	return _items.count;
}

- (id)tableView:(NSTableView*)aTableView objectValueForTableColumn:(NSTableColumn*)aTableColumn row:(NSInteger)rowIndex
{
	return [_items[rowIndex] objectForKey:aTableColumn.identifier];
}

- (void)tableViewSelectionDidChange:(NSNotification*)notification
{
	[self updateStatusText:self];
}

// ========================
// = Overload in subclass =
// ========================

- (void)updateItems:(id)sender
{
}

- (void)updateStatusText:(id)sender
{
	_statusTextField.stringValue = @"";
}
@end

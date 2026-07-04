import handleAddIpLists from './addIpLists.js';
import alpineInit from './alpineInit.js';
import handleAutoTrimInputs from './autoTrimInputs.js';
import handleClipboardCopy from './clipboardCopy.js';
import handleConfirmAction from './confirmAction.js';
import handleCopyCreds from './copyCreds.js';
import handleCronGenerator from './cronGenerator.js';
import handleDatabaseHints from './databaseHints.js';
import handleDiscardAllMail from './discardAllMail.js';
import handleDocRootHint from './docRootHint.js';
import handleEditWebListeners from './editWebListeners.js';
import handleErrorMessage from './errorHandler.js';
import focusFirstInput from './focusFirstInput.js';
import handleFormSubmit from './formSubmit.js';
import handleFtpAccountHints from './ftpAccountHints.js';
import handleFtpAccounts from './ftpAccounts.js';
import handleIpListDataSource from './ipListDataSource.js';
import handleListSorting from './listSorting.js';
import handleListUnitSelect from './listUnitSelect.js';
import handleNameServerInput from './nameServerInput.js';
import handlePasswordInput from './passwordInput.js';
import handleShortcuts from './shortcuts.js';
import handleStickyToolbar from './stickyToolbar.js';
import handleSyncEmailValues from './syncEmailValues.js';
import handleTabPanels from './tabPanels.js';
import handleToggleAdvanced from './toggleAdvanced.js';
import handleUnlimitedInput from './unlimitedInput.js';

initListeners();
focusFirstInput();

function initListeners() {
	handleAddIpLists();
	handleAutoTrimInputs();
	handleConfirmAction();
	handleCopyCreds();
	handleClipboardCopy();
	handleCronGenerator();
	handleDiscardAllMail();
	handleDocRootHint();
	handleEditWebListeners();
	handleFormSubmit();
	handleFtpAccounts();
	handleListSorting();
	handleListUnitSelect();
	handleNameServerInput();
	handlePasswordInput();
	handleStickyToolbar();
	handleSyncEmailValues();
	handleTabPanels();
	handleToggleAdvanced();

}

document.addEventListener('alpine:init', () => {
	alpineInit();
	handleDatabaseHints();
	handleErrorMessage();
	handleFtpAccountHints();
	handleIpListDataSource();
	handleShortcuts();
	handleUnlimitedInput();
});

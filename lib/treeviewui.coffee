{CompositeDisposable} = require 'atom'
path = require 'path'
fs = require 'fs-plus'
utils = require './utils'

module.exports = class TreeViewUI

  roots: null
  repositoryMap: null
  treeViewRootsMap: null
  subscriptions: null

  constructor: (@treeView, @repositoryMap) ->
    # Read configuration
    @showProjectModifiedStatus =
      atom.config.get 'tree-view-git-status.showProjectModifiedStatus'
    @showBranchLabel =
      atom.config.get 'tree-view-git-status.showBranchLabel'
    @showCommitsAheadLabel =
      atom.config.get 'tree-view-git-status.showCommitsAheadLabel'
    @showCommitsBehindLabel =
      atom.config.get 'tree-view-git-status.showCommitsBehindLabel'

    @subscriptions = new CompositeDisposable
    @treeViewRootsMap = new Map

    # Bind against events which are causing an update of the tree view
    @subscribeUpdateConfigurations()
    @subscribeUpdateTreeView()

    # Trigger inital update of all root nodes
    @updateRoots true

  destruct: ->
    @clearTreeViewRootMap()
    @subscriptions?.dispose()
    @subscriptions = null
    @treeViewRootsMap = null
    @repositoryMap = null
    @roots = null

  subscribeUpdateTreeView: ->
    @subscriptions.add(
      atom.project.onDidChangePaths =>
        @updateRoots true
    )
    @subscriptions.add(
      atom.config.onDidChange 'tree-view.hideVcsIgnoredFiles', =>
        @updateRoots true
    )
    @subscriptions.add(
      atom.config.onDidChange 'tree-view.hideIgnoredNames', =>
        @updateRoots true
    )
    @subscriptions.add(
      atom.config.onDidChange 'core.ignoredNames', =>
        @updateRoots true if atom.config.get 'tree-view.hideIgnoredNames'
    )
    @subscriptions.add(
      atom.config.onDidChange 'tree-view.sortFoldersBeforeFiles', =>
        @updateRoots true
    )

  setRepositories: (repositories) ->
    if repositories?
      @repositoryMap = repositories
      @updateRoots true

  clearTreeViewRootMap: ->
    @treeViewRootsMap?.forEach (root, rootPath) ->
      root.root?.classList?.remove('status-modified', 'status-added')
      customElements = root.customElements
      if customElements?.headerGitStatus?
        root.root?.header?.removeChild(customElements.headerGitStatus)
        customElements.headerGitStatus = null
    @treeViewRootsMap?.clear()

  updateRoots: (reset) ->
    if @repositoryMap?
      @roots = @treeView.roots
      @clearTreeViewRootMap() if reset
      for root in @roots
        rootPath = utils.normalizePath root.directoryName.dataset.path
        if reset
          @treeViewRootsMap.set(rootPath, {root, customElements: {}})
        repoForRoot = null
        repoSubPath = null
        rootPathHasGitFolder = fs.existsSync(path.join(rootPath, '.git'))
        @repositoryMap.forEach (repo, repoPath) ->
          if not repoForRoot? and ((rootPath is repoPath) or
              (rootPath.indexOf(repoPath) is 0 and not rootPathHasGitFolder))
            repoSubPath = path.relative repoPath, rootPath
            repoForRoot = repo
        if repoForRoot?
          if not repoForRoot?
            repoForRoot = null
          @doUpdateRootNode root, repoForRoot, rootPath, repoSubPath

  updateRootForRepo: (repo, repoPath) ->
    if @treeView? and @treeViewRootsMap?
      @treeViewRootsMap.forEach (root, rootPath) =>
        # Check if the root path is sub path of repo path
        repoSubPath = path.relative repoPath, rootPath
        if repoSubPath.indexOf('..') isnt 0
          @doUpdateRootNode root.root, repo, rootPath, repoSubPath if root.root?

  doUpdateRootNode: (root, repo, rootPath, repoSubPath) ->
    customElements = @treeViewRootsMap.get(rootPath).customElements
    updatePromise = Promise.resolve()

    if @showProjectModifiedStatus and repo?
      updatePromise = updatePromise.then () ->
        if repoSubPath isnt ''
          return repo.getDirectoryStatus repoSubPath
        else
          # Workaround for the issue that 'getDirectoryStatus' doesn't work
          # on the repository root folder
          return utils.getRootDirectoryStatus repo

    updatePromise.then (status) =>
      # Sanity check...
      return unless @roots?

      convStatus = @convertDirectoryStatus repo, status
      root.classList.remove('status-modified', 'status-added')
      root.classList.add("status-#{convStatus}") if convStatus?

      showHeaderGitStatus = @showBranchLabel or @showCommitsAheadLabel or
          @showCommitsBehindLabel

      if showHeaderGitStatus and repo? and not customElements.headerGitStatus?
        headerGitStatus = document.createElement('span')
        headerGitStatus.classList.add('tree-view-git-status')
        customElements.headerGitStatus = headerGitStatus
        return @generateGitStatusText(headerGitStatus, repo).then ->
          root.header.insertBefore(
            headerGitStatus, root.directoryName.nextSibling
          )
      else if showHeaderGitStatus and customElements.headerGitStatus?
        return @generateGitStatusText customElements.headerGitStatus, repo
      else if customElements.headerGitStatus?
        root.header.removeChild(customElements.headerGitStatus)
        customElements.headerGitStatus = null

  generateGitStatusText: (container, repo) ->
    display = false
    head = null
    ahead = behind = 0

    # Ensure repo status is up-to-date
    repo.refreshStatus()
      .then ->
        return repo.getShortHead()
          .then((shorthead) ->
            head = shorthead
          )
      .then ->
        # Sanity check in case of thirdparty repos...
        if repo.getCachedUpstreamAheadBehindCount?
          return repo.getCachedUpstreamAheadBehindCount()
          .then((count) ->
            {ahead, behind} = count
          )
      .then =>
        if @showBranchLabel and head?
          branchLabel = document.createElement('span')
          branchLabel.classList.add('branch-label')
          branchLabel.textContent = head
          display = true
        if @showCommitsAheadLabel and ahead > 0
          commitsAhead = document.createElement('span')
          commitsAhead.classList.add('commits-ahead-label')
          commitsAhead.textContent = ahead
          display = true
        if @showCommitsBehindLabel and behind > 0
          commitsBehind = document.createElement('span')
          commitsBehind.classList.add('commits-behind-label')
          commitsBehind.textContent = behind
          display = true

        if display
          container.classList.remove('hide')
        else
          container.classList.add('hide')

        container.innerHTML = ''
        container.appendChild branchLabel if branchLabel?
        container.appendChild commitsAhead if commitsAhead?
        container.appendChild commitsBehind if commitsBehind?

  convertDirectoryStatus: (repo, status) ->
    newStatus = null
    if repo.isStatusModified(status)
      newStatus = 'modified'
    else if repo.isStatusNew(status)
      newStatus = 'added'
    return newStatus

  getRootDirectoryStatus: (repo) ->
    directoryStatus = 0
    for filePath, status of repo.statuses
      directoryStatus |= status
    return directoryStatus

  subscribeUpdateConfigurations: ->
    @subscriptions.add(
      atom.config.observe 'tree-view-git-status.showProjectModifiedStatus',
        (newValue) =>
          if @showProjectModifiedStatus isnt newValue
            @showProjectModifiedStatus = newValue
            @updateRoots()
    )
    @subscriptions.add(
      atom.config.observe 'tree-view-git-status.showBranchLabel',
        (newValue) =>
          if @showBranchLabel isnt newValue
            @showBranchLabel = newValue
            @updateRoots()
   )
    @subscriptions.add(
      atom.config.observe 'tree-view-git-status.showCommitsAheadLabel',
        (newValue) =>
          if @showCommitsAheadLabel isnt newValue
            @showCommitsAheadLabel = newValue
            @updateRoots()
    )
    @subscriptions.add(
      atom.config.observe 'tree-view-git-status.showCommitsBehindLabel',
        (newValue) =>
          if @showCommitsBehindLabel isnt newValue
            @showCommitsBehindLabel = newValue
            @updateRoots()
    )

{CompositeDisposable} = require 'atom'
ProjectRepositories = require './repositories'
TreeViewUI = require './treeviewui'

module.exports = TreeViewGitStatus =

  config:
    autoToggle:
      type: 'boolean'
      default: true
    showProjectModifiedStatus:
      type: 'boolean'
      default: true
      description:
        'Mark project folder as modified in case there are any ' +
        'uncommited changes'
    showBranchLabel:
      type: 'boolean'
      default: true
    showCommitsAheadLabel:
      type: 'boolean'
      default: true
    showCommitsBehindLabel:
      type: 'boolean'
      default: true

  subscriptions: null
  toggledSubscriptions: null
  treeView: null
  subscriptionsOfCommands: null
  active: false
  repos: null
  treeViewUI: null

  activate: ->
    @subscriptionsOfCommands = new CompositeDisposable
    @subscriptions = new CompositeDisposable
    @subscriptions.add atom.packages.onDidActivateInitialPackages =>
      @doInitPackage()
    @doInitPackage()

  doInitPackage: ->
    # Check if the tree view has been already initialized
    treeView = @getTreeView()
    return unless treeView

    @treeView = treeView
    @active = true

    # Toggle tree-view-git-status...
    @subscriptionsOfCommands.add atom.commands.add 'atom-workspace',
      'tree-view-git-status:toggle': =>
        @toggle()
    autoToggle = atom.config.get 'tree-view-git-status.autoToggle'
    @toggle() if autoToggle

  deactivate: ->
    @subscriptions?.dispose()
    @subscriptionsOfCommands?.dispose()
    @subscriptions = null
    @treeView = null
    @active = false
    @toggled = false

  toggle: ->
    return unless @active
    if not @toggled
      @toggled = true
      @repos = new ProjectRepositories
      @treeViewUI = new TreeViewUI @treeView, @repos.getRepositories()
      @toggledSubscriptions = new CompositeDisposable
      @toggledSubscriptions.add(
        @repos.onDidChange 'repos', (repos) =>
          @treeViewUI?.setRepositories repos
      )
      @toggledSubscriptions.add(
        @repos.onDidChange 'repo-status', (evt) =>
          if @repos?.getRepositories().has(evt.repoPath)
            @treeViewUI?.updateRootForRepo(evt.repo, evt.repoPath)
      )
    else
      @toggled = false
      @subscriptions?.dispose()
      @subscriptions = null
      @toggledSubscriptions?.dispose()
      @toggledSubscriptions = null
      @repos?.destruct()
      @repos = null
      @treeViewUI?.destruct()
      @treeViewUI = null

  getTreeView: ->
    if not @treeView?
      if atom.packages.getActivePackage('tree-view')?
        treeViewPkg = atom.packages.getActivePackage('tree-view')
      # TODO Check for support of Nuclide Tree View
      if treeViewPkg?.mainModule?.treeView?
        return treeViewPkg.mainModule.treeView
      else
        return null
    else
      return @treeView

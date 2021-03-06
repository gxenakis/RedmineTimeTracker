timeTracker.factory("Project", ($q, Task, Analytics, Platform, Const, Log) ->

  ###*
   Project data model.
   @class ProjectModel
  ###
  class ProjectModel extends Task

    UPDATED: "updated"

    ###*
     constructor.
     @constructor
     @param {String} url - Redmine server's url.
     @param {Number} urlIndex - Project id's index on Platform.storage.
     @param {Number} id - Project id.
     @param {String} text - Project's name.
     @param {Number} show - Can this project show? (DEFAULT: 0, NOT: 1, SHOW: 2)
     @param {Number} queryId - Used query ID
    ###
    constructor: (@url, urlIndex, id, @text, show, queryId) ->
      super(id, text, url, id, 0, Const.TASK_TYPE.PROJECT)
      @id = id - 0
      isNaN(urlIndex) or @urlIndex = urlIndex - 0
      isNaN(show) or @show = show - 0
      isNaN(queryId) or @queryId = queryId - 0
      Const.ISSUE_PROPS.map (p) => @[p] = []
      @_tickets = []
      @tickets = new Proxy(@_tickets, @updateProperties(@))

    ###*
     Update property related to project.
     @param {ProjectModel} projectModel - target project.
    ###
    updateProperties: (projectModel) ->

      # Initialize property map.
      tmp = {}
      Const.ISSUE_PROPS.map (prop) -> tmp[prop] = {}

      return {

        ###*
         Properties map on this project.
         @type {Object}
        ###
        _props: tmp

        ###*
         Called on ticket changes.
         @param {Array} tickets - Target object.
         @param {String} index - Property name.
         @param {TicketModel} ticket - New ticket.
        ###
        set: (tickets, index, ticket) ->
          Log.time("updateProperties #{projectModel.text}\t")
          if tickets.isEmpty()
            for prop, val of @_props
              for p, v of val then delete val[p]
          # create each property's id/name object. Id must be unique.
          Const.ISSUE_PROPS.map (prop) =>
            ticket[prop] and @_props[prop][ticket[prop].id] = ticket[prop].name
          Const.ISSUE_PROPS.map (prop) =>
            # create id/name pair array.
            tmpArray = Object.toKeyValuePair(@_props[prop], {key: "id", value: "name"})
            tmpArray.add({id: "", name: "All"}, 0)
            tmpArray.map (t) -> t.checked = true
            # restore old checked status
            projectModel[prop].map (oldOption) ->
              newOption = tmpArray.find (n) -> n.id is oldOption.id
              newOption.checked = oldOption.checked if newOption
            projectModel[prop].set(tmpArray)
          # set changed ticket
          tickets[index] = ticket
          Log.timeEnd("updateProperties #{projectModel.text}\t")
          # Log.info(projectModel)
          projectModel.fireEvent(projectModel.UPDATED, projectModel)
          return true
      }


  ###*
   Class for management ProjectModels.
   @class Project
   @constructor
  ###
  class Project

    # class variables
    @PROJECT = "PROJECT"

    ###*
     @typedef {Object} ProjectOptions
     @prop {string} text - Project name.
     @prop {number} show - Represents whether this project will be shown on this app.
     @prop {number} queryId - Used query ID in this project.
    ###

    ###*
     @typedef {Object} ProjectData
     @prop {number} index - The index number of the project at the same URL.
     @prop {Object.<string, ProjectOptions>} <key> - Project id.
    ###

    ###*
     Projects object on storage. ProjectModels are saved on storage using this format.
     @typedef {Object} ProjectDataSet
     @prop {Object.<string, ProjectData>} <key> - Project's url.
    ###

    ###*
     Convert projects to format of chrome. all projects are unique.
     @param {ProjectModel[]} projects - array of ProjectModel
     @return {ProjectDataSet} Project object on chrome format.
    ###
    _toChromeObjects: (projects) ->
      return {} if not projects
      result = {}
      projects.map (prj) ->
        # initialize if not exists
        result[prj.url] = result[prj.url] or {}
        target = result[prj.url][prj.id] = result[prj.url][prj.id] or {}
        # set params
        if result[prj.url].index >= 0
          prj.urlIndex = result[prj.url].index
        else
          prj.urlIndex = Object.keys(result).length - 1
        result[prj.url].index = prj.urlIndex
        target.show    = if prj.show? then prj.show else target.show
        target.queryId = if prj.queryId? then prj.queryId else target.queryId
      return result


    ###*
     Convert projects to ProjectModel.
     @param {Object} projects - Project object on chrome format.
     @return {Array} Array of ProjectModel
    ###
    _toProjectModels: (projects) ->
      result = []
      for url, obj of projects
        for k, v of obj
          continue if k is "index"
          result.push new ProjectModel(url,
                                       obj.index - 0,
                                       k - 0,
                                       v.text,
                                       v.show - 0,
                                       v.queryId - 0)
      return result


    ###*
     Load all projects from storage.
     @return {Promise.<ProjectModel[]>} Loaded ProjectModels
    ###
    load: () =>
      Log.debug "Project.load() start"
      return Platform.load(Project.PROJECT)
        .then((projects) =>
          if not projects
            Log.info 'Project does not exists, initialized.'
            projects = {}
          Analytics.sendEvent 'project', 'count', 'onLoad', projects.length
          Log.debug "Project.load() loaded"
          return @_toProjectModels(projects)
        , () ->
          Analytics.sendEvent 'project', 'count', 'onLoad', 0
          Log.debug "Project.load() failed"
          return $q.reject(null))


    ###*
     Sync all projects to storage.
     @param {ProjectModel[]} projects - Array of ProjectModel.
     @return {Promise.<undefined>} A promise for result of saving.
    ###
    sync: (projects) ->
      data = @_toChromeObjects(projects)
      Platform.save(Project.PROJECT, data)
        .then((res) ->
          Log.info 'project synced.'
          Analytics.sendEvent 'project', 'sync', 'success', 1
          return res
        , (res) ->
          Log.info 'project sync failed.'
          Analytics.sendEvent 'project', 'sync', 'failed', 1
          return res)


    ###*
     Save all projects to local storage area.
     @param {ProjectModel[]} projects - Array of ProjectModel.
     @return {Promise.<undefined>} A promise for result of saving.
    ###
    syncLocal: (projects) ->
      data = @_toChromeObjects(projects)
      Platform.saveLocal(Project.PROJECT, data)
      .then((res) ->
        Log.info 'project synced.'
        Analytics.sendEvent 'project', 'sync', 'success', 1
        return res
      , (res) ->
        Log.info 'project sync failed.'
        Analytics.sendEvent 'project', 'sync', 'failed', 1
        return res)


    ###*
     create new Model instance.
    ###
    create: (params) ->
      new ProjectModel(params.url,
                       params.urlIndex,
                       params.id,
                       params.text,
                       params.show,
                       params.queryId)


  return new Project()

)

window.h = maquette.h

class ZeroHello extends ZeroFrame
	init: ->
		@params = {}
		@site_info = null
		@server_info = null
		@announcer_info = null
		@announcer_stats = null
		@address = null

		@on_site_info = new Promise()
		@on_server_info = new Promise()
		@on_settings = new Promise()
		@on_loaded = new Promise()
		@settings = null

		@server_errors = []

		@latest_version = "0.8.0"
		@latest_rev = 4591
		@mode = "Sites"
		@change_timer = null
		document.body.id = "Body#{@mode}"

	addRenderer: (node, renderer) ->
		@projector.replace(node, renderer)
		@renderers.push(renderer)

	detachRenderers: ->
		for renderer in @renderers
			@projector.detach(renderer)
		@renderers = []

	setProjectorMode: (mode) ->
		@log "setProjectorMode", mode
		if @mode == mode
			return

		@detachRenderers()
		if mode == "Files"
			@addRenderer($("#PageFiles"), @page_files.render)
			@page_files.need_update = true
		else if mode == "Stats"
			@addRenderer($("#PageStats"), @page_stats.render)
			@page_stats.need_update = true
		else
			mode = "Sites"
			@addRenderer($("#FeedList"), @feed_list.render)
			@addRenderer($("#SiteList"), @site_list.render)

		@mode = mode
		setTimeout ( ->
			# Delayed to avoid loosing anmation because of dom re-creation
			document.body.id = "Body#{mode}"

			if @change_timer
				clearInterval @change_timer
			document.body.classList.add("changing")
			@change_timer = setTimeout ( ->
				document.body.classList.remove("changing")
			), 800

		), 60


	createProjector: ->
		@projector = maquette.createProjector()  # Dummy, will set later
		@projectors = {}
		@renderers = []

		@site_list = new SiteList()
		@feed_list = new FeedList()
		@page_files = new PageFiles()
		@page_stats = new PageStats()
		@head = new Head()
		@dashboard = new Dashboard()
		@mute_list = new MuteList()
		@trigger = new Trigger()

		if base.href.indexOf("?") == -1
			@route("")
		else
			url = base.href.replace(/.*?\?/, "")
			@route(url)
			@history_state["url"] = url

		@loadSettings()
		@on_site_info.then =>
			@projector.replace($("#Head"), @head.render)
			@projector.replace($("#Dashboard"), @dashboard.render)
			@projector.merge($("#Trigger"), @trigger.render)
			@setProjectorMode(@mode)

		# Update every minute to keep time since fields up-to date
		setInterval ( ->
			Page.projector.scheduleRender()
		), 60*1000


	# Route site urls
	route: (query) ->
		@params = Text.parseQuery(query)
		@log "Route", @params
		@setProjectorMode(@params.url)
		if @mode == "Stats"
			@page_stats.need_update = true
		else if @mode == "Files"
			@page_files.need_update = true
		@projector.scheduleRender()

	# Add/remove/change parameter to current site url
	createUrl: (key, val) ->
		params = JSON.parse(JSON.stringify(@params))  # Clone
		if typeof key == "Object"
			vals = key
			for key, val of keys
				params[key] = val
		else
			params[key] = val
		return "?"+Text.encodeQuery(params)

	setUrl: (url, mode="replace") ->
		url = url.replace(/.*?\?/, "")
		@log "setUrl", @history_state["url"], "->", url
		if @history_state["url"] == url
			return false
		@history_state["url"] = url
		if mode == "replace"
			@cmd "wrapperReplaceState", [@history_state, "", url]
		else
			@cmd "wrapperPushState", [@history_state, "", url]
		@route url
		return false

	handleLinkClick: (e) =>
		if e.which == 2
			# Middle click dont do anything
			return true
		else
			@log "save scrollTop", window.pageYOffset
			@history_state["scrollTop"] = window.pageYOffset
			@cmd "wrapperReplaceState", [@history_state, null]

			window.scroll(window.pageXOffset, 0)
			@history_state["scrollTop"] = 0

			@setUrl e.currentTarget.search
			return false

	loadSettings: ->
		@on_site_info.then =>
			@cmd "userGetSettings", [], (res) =>
				if not res or res.error
					@loadLocalStorage()
				else
					@settings = res
					@settings.sites_orderby ?= "peers"
					@settings.sites_section_hide ?= {}
					@settings.favorite_sites ?= {}
					@settings.siteblocks_ignore ?= {}
					@settings.date_feed_visit ?= 1
					@feed_list.date_feed_visit = @settings.date_feed_visit
					@on_settings.resolve(@settings)

	loadLocalStorage: ->
		@cmd "wrapperGetLocalStorage", [], (@settings) =>
			@log "Loaded localstorage"
			@settings ?= {}
			@settings.sites_orderby ?= "peers"
			@settings.favorite_sites ?= {}
			@on_settings.resolve(@settings)

	saveSettings: (cb) ->
		if @settings
			if Page.server_info.rev > 2140
				@cmd "userSetSettings", [@settings], (res) =>
					if cb then cb(res)
			else
				@cmd "wrapperSetLocalStorage", @settings, (res) =>
					if cb then cb(res)


	onOpenWebsocket: (e) =>
		@reloadServerInfo()
		@reloadServerErrors()
		@reloadSiteInfo()

	reloadSiteInfo: =>
		@cmd "siteInfo", {}, (site_info) =>
			@address = site_info.address
			@setSiteInfo(site_info)

	reloadServerInfo: (cb) =>
		@cmd "serverInfo", {}, (server_info) =>
			@setServerInfo(server_info)
			cb?(server_info)

	reloadServerErrors: (cb) =>
		@on_server_info.then =>
			if @server_info.multiuser and not @server_info.multiuser_admin
				return cb?(false)
			@cmd "serverErrors", {}, (server_errors) =>
				@setServerErrors(server_errors)
				cb?(server_errors)

	reloadAnnouncerInfo: (cb) =>
		@cmd "announcerInfo", {}, (announcer_info) =>
			@setAnnouncerInfo(announcer_info)
			cb?()

	reloadAnnouncerStats: (cb) =>
		@cmd "announcerStats", {}, (announcer_stats) =>
			@announcer_stats = announcer_stats
			Page.projector.scheduleRender()
			cb?()

	# Parse incoming requests from UiWebsocket server
	onRequest: (cmd, params) ->
		if cmd == "setSiteInfo" # Site updated
			@setSiteInfo(params)
		else if cmd == "setServerInfo"
			@setServerInfo(params)
		else if cmd == "setAnnouncerInfo"
			@setAnnouncerInfo(params)
		else
			@log "Unknown command", params

	setSiteInfo: (site_info) ->
		if site_info.address == @address
			@site_info = site_info
			if @server_info?.rev > 3530
				@reloadAnnouncerStats()
			else if @server_info?.rev > 3460
				@reloadAnnouncerInfo()
		@site_list.onSiteInfo(site_info)
		@feed_list.onSiteInfo(site_info)
		@page_files.onSiteInfo(site_info)
		@on_site_info.resolve()

	setServerInfo: (server_info) ->
		@server_info = server_info
		if parseFloat(Page.server_info.version.replace(/\./g, "0")) < 700
			@latest_version = "0.6.5"
		@projector.scheduleRender()
		if server_info.event?[0] == "log_event"
			RateLimit 1000, =>
				@reloadServerErrors()
		@on_server_info.resolve()

	setServerErrors: (server_errors) ->
		@server_errors = []
		for [date_added, level, message] in server_errors
			@server_errors.push({
				title: [Time.since(date_added), " - ", level],
				descr: message,
				href: "#ZeroNet:Console:Error"
			})
		@projector.scheduleRender()

	setAnnouncerInfo: (announcer_info) ->
		@announcer_info = announcer_info.stats
		@projector.scheduleRender()

	# Simple return false to avoid link clicks
	returnFalse: ->
		return false

	updateZeronet: ->
		if @server_info.updatesite  # Python3 version: Go to site
			window.top.location = Text.getSiteUrl(@server_info.updatesite)
		else
			Page.cmd "wrapperNotification", ["info", "Updating to latest version...<br>Please restart ZeroNet manually if it does not come back in the next few minutes.", 8000]
			Page.cmd "serverUpdate"


window.Page = new ZeroHello()
window.Page.createProjector()

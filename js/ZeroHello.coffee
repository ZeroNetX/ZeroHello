class ZeroHello extends ZeroFrame
	init: ->
		@log "inited!"
		@sites = {}
		$(".button-update").on "click", =>
			$(".button-update").addClass("loading")
			@cmd "serverUpdate", {}


	# Wrapper websocket connection ready
	onOpenWebsocket: (e) =>
		@reloadPeers()
		@reloadSites()
		@reloadServerInfo()
		$(".button-update").removeClass("loading")
		@cmd "channelJoinAllsite", {"channel": "siteChanged"}


	# Route incoming requests
	route: (cmd, message) ->
		if cmd == "setSiteInfo"
			@actionSetSiteInfo(message)
		else
			@log "Unknown command", message


	# - Incoming requests -

	actionSetSiteInfo: (message) ->
		site = message.params
		@applySitedata($(".site-#{site.address}"), site)


	# Format time since	
	formatSince: (time) ->
		now = +(new Date)/1000
		secs = now - time
		if secs < 60
			back = "Just now"
		else if secs < 60*60
			back = "#{Math.round(secs/60)} minutes ago"
		else if secs < 60*60*24
			back = "#{Math.round(secs/60/60)} hours ago"
		else if secs < 60*60*24*3
			back = "#{Math.round(secs/60/60/24)} days ago"
		else
			back = "on "+@formatDate(time)
		back = back.replace(/1 ([a-z]+)s/, "1 $1") # 1 days ago fix
		return back


	# Format timestamp to date
	formatDate: (timestamp, format="short") ->
		parts = (new Date(timestamp*1000)).toString().split(" ")
		if format == "short"
			display = parts.slice(1, 4)
		else
			display = parts.slice(1, 5)
		return display.join(" ").replace(/( [0-9]{4})/, ",$1")


	# Reload site peer number
	reloadPeers: ->
		@cmd "siteInfo", {}, (site_info) =>
			@address = site_info.addres
			peers = site_info["peers"]
			if peers == 0 then peers = "n/a"
			$("#peers").removeClass("updating").text(peers)


	# Apple site data to html element
	applySitedata: (elem, site) ->
		# Backward compatibility
		if typeof(site.bad_files) == "object" then site.bad_files = site.bad_files.length
		if typeof(site.tasks) == "object" then site.tasks = site.tasks.length

		elem.addClass("site-#{site.address}")
		if site.peers
			$(".peers", elem).html(site.peers)
		else
			$(".peers", elem).html("n/a")
		if site.content.title.length > 20
			$(".title", elem).html(site.content.title).addClass("long")
		else
			$(".title", elem).html(site.content.title).removeClass("long")
		$(".description", elem).html(site.content.description)
		modified = if site.settings.modified then site.settings.modified else site.content.modified
		$(".modified", elem).html @formatSince(modified)
		$(".site", elem).attr("href", "/"+site.address)

		$(elem).removeClass("site-seeding").removeClass("site-paused")
		if site.settings.serving and site.address # Seeding
			$(elem).addClass("site-seeding")
			$(".status", elem).text("Seeding")
		else # Paused
			$(elem).addClass("site-paused")
			$(".status", elem).text("Paused")


		# Show/hide loading
		if site.tasks > 0 # Site tasks running
			$(".anim-updating", elem).addClass("visible")
		else
			$(".anim-updating", elem).removeClass("visible")

		# Show success
		if site.event?[0] == "file_done" or site.event?[0] == "file_started"
			if site.bad_files > 0
				success = "Updating: #{site.bad_files} left"
			else if site.event[0] == "file_done" and site.bad_files == 0
				success = "Site updated"
		if success
			$(".notify", elem).text(success).addClass("success").addClassLater("visible")

		# Show error
		if site.content_updated == false
			if site.settings.own
				error = "No peers found"
			else
				error = "Update failed"
		else if site.tasks == 0 and site.bad_files > 0 and site.event?[0] != "file_done"
			error = "#{site.bad_files} file update failed"
		if error
			$(".notify", elem).text(error).removeClass("success").addClassLater("visible")

		# Hide error/success
		if not error and not success
			$(".notify", elem).removeClass("visible")

		# Disabled
		if site.disabled # No address for site
			$(elem).addClass("site-disabled")

		# Add menu events
		$(".hamburger", elem).off("click").on "click", (-> new SiteMenu(elem, site).show(); return false )

		@sites[site.address] = site

		if site.address == @address and site.peers > 0 then $("#peers").text(site.peers) # Update servedby text

		return elem


	# Reload sites div content
	reloadSites: ->
		@cmd "siteList", {}, (sites) =>
			$("#sites > :not(.template)").remove()

			# Append Active sites category marker
			elem_category = $(".site-category.template").clone()
			elem_category.removeClass("template")
			$("#sites").append elem_category

			sites.sort (a,b) ->
				return cmp b["peers"], a["peers"]

			# Append active sites
			for site in sites
				elem = $(".site-container.template").clone().removeClass("template")
				elem = @applySitedata(elem, site)

				$("#sites").append elem

			# Append Sample sites marker
			elem_category = $(".site-category.template").clone()
			elem_category.removeClass("template")
			$(".title", elem_category).html("Sample sites")
			$("#sites").append elem_category

			# Append sample sites
			sample_sites = [
				{"content": {"title": "ZeroBoard", "description": "Messaging board demo"}, "address": "1Gfey7wVXXg1rxk751TBTxLJwhddDNfcdp", "settings": {"serving": false}}
				{"content": {"title": "ZeroBlog", "description": "Blogging platform Demo"}, "address": "1BLogC9LN4oPDcruNz3qo1ysa133E9AGg8", "settings": {"serving": false}}
				{"content": {"title": "ZeroTalk", "description": "Decentralized forum demo"}, "address": "1TaLk3zM7ZRskJvrh3ZNCDVGXvkJusPKQ", "settings": {"serving": false}}
				{"content": {"title": "ZeroMarket", "description": "Simple market demo (coming soon)"}, "address": "ZeroMarket", "disabled": true, "settings": {"serving": false}}
			]

			for site in sample_sites
				if $(".site-#{site.address}").length > 0 then continue # Already using this site, continue
				elem = $(".site-container.template").clone().removeClass("template").addClass("site-inactive")
				elem = @applySitedata(elem, site)
				$(".status, .right, .bottom", elem).css("display", "none") # Hide data we dont have
				$(".action", elem).html("Activate site &#9473;")

				$("#sites").append elem
			# Show sites
			$("#sites").removeClass("updating")
			$("#sites").css("height", "auto") # Back to auto height


	# Reload serverinfo
	reloadServerInfo: ->
		@cmd "serverInfo", {}, (serverInfo) =>
			@serverInfo = serverInfo
			
			# Check verion info
			version = serverInfo.version
			if not version then version = "Unknown, please update" # Old version websocket api didnt had version info
			$(".version .current a").html(version)
			if $(".version .latest a").text() == version # No new version available
				$(".version .latest").css "display", "none"
				$(".button-update").css "display", "none"
			else
				$(".version .latest").css "display", "inline-block"
				if parseInt(version.replace(/[^0-9]/g, "0")) >= 202 then $(".button-update").css "display", "inline-block" # Auto update supported from 0.2.3
			$(".version").css("opacity", 1)


	# - Site commands -

	# Update site content.json
	siteUpdate: (address) ->
		@cmd "siteUpdate", {"address": address}


	# Pause site from seeding
	sitePause: (address) ->
		@cmd "sitePause", {"address": address}


	# Resume site seeding
	siteResume: (address) ->
		@cmd "siteResume", {"address": address}


	# Delete site
	siteDelete: (address) ->
		site = @sites[address]
		if site.settings.own
			@cmd "wrapperNotification", ["error", "Sorry, you can't delete your own site.<br>Please remove the directory manually."]
		else
			title = site.content.title
			if title.length > 40
				title = title.substring(0, 15)+"..."+title.substring(title.length-10)
			@cmd "wrapperConfirm", ["Are you sure you sure? <b>#{title}</b>", "Delete"], (confirmed) =>
				@log "Deleting #{site.address}...", confirmed
				if confirmed
					$(".site-#{site.address}").addClass("deleted")
					@cmd "siteDelete", {"address": address}


window.zero_hello = new ZeroHello()

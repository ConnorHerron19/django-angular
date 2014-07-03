###
# Copyright (C) 2014 Andrey Antukh <niwi@niwi.be>
# Copyright (C) 2014 Jesús Espino Garcia <jespinog@gmail.com>
# Copyright (C) 2014 David Barragán Merino <bameda@dbarragan.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#
# File: modules/backlog/main.coffee
###

taiga = @.taiga

mixOf = @.taiga.mixOf
toggleText = @.taiga.toggleText
scopeDefer = @.taiga.scopeDefer
bindOnce = @.taiga.bindOnce
groupBy = @.taiga.groupBy

module = angular.module("taigaBacklog")

#############################################################################
## Backlog Controller
#############################################################################

class BacklogController extends mixOf(taiga.Controller, taiga.PageMixin)
    @.$inject = [
        "$scope",
        "$rootScope",
        "$tgRepo",
        "$tgConfirm",
        "$tgResources",
        "$routeParams",
        "$q"
    ]

    constructor: (@scope, @rootscope, @repo, @confirm, @rs, @params, @q) ->
        _.bindAll(@)

        @scope.sectionName = "Backlog"

        promise = @.loadInitialData()
        promise.then null, =>
            console.log "FAIL"

        @scope.$on("usform:bulk:success", @.loadUserstories)
        @scope.$on("sprintform:create:success", @.loadSprints)
        @scope.$on("sprintform:create:success", @.loadProjectStats)
        @scope.$on("usform:new:success", @.loadUserstories)
        @scope.$on("usform:edit:success", @.loadUserstories)

    loadProjectStats: ->
        return @rs.projects.stats(@scope.projectId).then (stats) =>
            @scope.stats = stats
            completedPercentage = Math.round(100 * stats.closed_points / stats.total_points)
            @scope.stats.completedPercentage = "#{completedPercentage}%"
            return stats

    loadSprints: ->
        return @rs.sprints.list(@scope.projectId).then (sprints) =>
            @scope.sprints = sprints
            return sprints

    loadUserstories: ->
        return @rs.userstories.listUnassigned(@scope.projectId).then (userstories) =>
            @scope.userstories = userstories
            @scope.filters = @.generateFilters()

            @.filterVisibleUserstories()
            # The broadcast must be executed when the DOM has been fully reloaded.
            # We can't assure when this exactly happens so we need a defer
            scopeDefer @scope, =>
                @scope.$broadcast("userstories:loaded")

            return userstories

    loadBacklog: ->
        return @q.all([
            @.loadProjectStats(),
            @.loadSprints(),
            @.loadUserstories()
        ])

    loadProject: ->
        return @rs.projects.get(@scope.projectId).then (project) =>
            @scope.project = project
            @scope.points = _.sortBy(project.points, "order")
            @scope.pointsById = groupBy(project.points, (x) -> x.id)
            @scope.usStatusById = groupBy(project.us_statuses, (x) -> x.id)
            @scope.usStatusList = _.sortBy(project.us_statuses, "id")
            return project

    loadInitialData: ->
        # Resolve project slug
        promise = @repo.resolve({pslug: @params.pslug}).then (data) =>
            @scope.projectId = data.project
            return data

        return promise.then(=> @.loadProject())
                      .then(=> @.loadUsersAndRoles())
                      .then(=> @.loadBacklog())

    filterVisibleUserstories: ->
        selectedTags = _.filter(@scope.filters.tags, "selected")
        selectedTags = _.map(selectedTags, "name")

        @scope.visibleUserstories = []

        if selectedTags.length == 0
            @scope.visibleUserstories = _.clone(@scope.userstories, false)
        else
            @scope.visibleUserstories = _.reject @scope.userstories, (us) =>
                if _.intersection(selectedTags, us.tags).length == 0
                    return true
                else
                    return false

    generateFilters: ->
        filters = {}
        plainTags = _.flatten(_.map(@scope.userstories, "tags"))
        filters.tags = _.map(_.countBy(plainTags), (v, k) -> {name: k, count:v})
        return filters

    ## Template actions

    editUserStory: (us) ->
        @rootscope.$broadcast("usform:edit", us)

    deleteUserStory: (us) ->
        #TODO: i18n
        title = "Delete User Story"
        subtitle = us.subject

        @confirm.ask(title, subtitle).then =>
            # We modify the userstories in scope so the user doesn't see the removed US for a while
            @scope.userstories = _.without(@scope.userstories, us);
            @filterVisibleUserstories()
            @.repo.remove(us).then =>
                @.loadBacklog()

    addNewUs: (type) ->
        switch type
            when "standard" then @rootscope.$broadcast("usform:new")
            when "bulk" then @rootscope.$broadcast("usform:bulk")

    addNewSprint: () ->
        @rootscope.$broadcast("sprintform:create")

module.controller("BacklogController", BacklogController)


#############################################################################
## Backlog Directive
#############################################################################

BacklogDirective = ($repo, $rootscope) ->
    #########################
    ## Doom line Link
    #########################

    linkDoomLine = ($scope, $el, $attrs, $ctrl) ->

        removeDoomlineDom = ->
            $el.find(".doom-line").remove()

        addDoomLineDom = (element) ->
            element?.before($( "<hr>", { class:"doom-line"}))

        getUsItems = ->
            rowElements = $el.find('.backlog-table-body .us-item-row')
            return _.map(rowElements, (x) -> angular.element(x))

        reloadDoomlineLocation = () ->
            bindOnce $scope, "stats", (project) ->
                removeDoomlineDom()

                elements = getUsItems()
                stats = $scope.stats

                total_points = stats.total_points
                current_sum = stats.assigned_points

                for element in elements
                    scope = element.scope()

                    if not scope.us?
                        continue

                    current_sum += scope.us.total_points
                    if current_sum > total_points
                        addDoomLineDom(element)
                        break

        bindOnce $scope, "stats", (project) ->
            reloadDoomlineLocation()
            $scope.$on("userstories:loaded", reloadDoomlineLocation)
            $scope.$on("doomline:redraw", reloadDoomlineLocation)

    #########################
    ## Drag & Drop Link
    #########################

    linkSortable = ($scope, $el, $attrs, $ctrl) ->
        resortAndSave = ->
            toSave = []
            for item, i in $scope.userstories
                if item.order == i
                    continue
                item.order = i

            toSave = _.filter($scope.userstories, (x) -> x.isModified())
            $repo.saveAll(toSave).then ->
                console.log "FINISHED", arguments

        onUpdateItem = (event) ->
            console.log "onUpdate", event

            item = angular.element(event.item)
            itemScope = item.scope()

            ids = _.map($scope.userstories, "id")
            index = ids.indexOf(itemScope.us.id)

            $scope.userstories.splice(index, 1)
            $scope.userstories.splice(item.index(), 0, itemScope.us)

            resortAndSave()

        onAddItem = (event) ->
            console.log "onAddItem", event
            item = angular.element(event.item)
            itemScope = item.scope()
            itemIndex = item.index()

            itemScope.us.milestone = null
            userstories = $scope.userstories
            userstories.splice(itemIndex, 0, itemScope.us)

            item.remove()
            item.off()

            $scope.$apply()
            resortAndSave()

        onRemoveItem = (event) ->
            console.log "onRemoveItem", event
            item = angular.element(event.item)
            itemScope = item.scope()

            ids = _.map($scope.userstories, "id")
            index = ids.indexOf(itemScope.us.id)

            if index != -1
                userstories = $scope.userstories
                userstories.splice(index, 1)

            item.off()
            itemScope.$destroy()

        dom = $el.find(".backlog-table-body")
        sortable = new Sortable(dom[0], {
            group: "backlog",
            selector: ".us-item-row",
            onUpdate: onUpdateItem
            onAdd: onAddItem
            onRemove: onRemoveItem
        })

    ##############################
    ## Move to current sprint link
    ##############################

    linkToolbar = ($scope, $el, $attrs, $ctrl) ->
        moveToCurrentSprint = (selectedUss) ->
            ussCurrent = _($scope.userstories)

            # Remove them from backlog
            $scope.userstories = ussCurrent.without.apply(ussCurrent, selectedUss).value()

            extraPoints = _.map(selectedUss, (v, k) -> v.total_points)
            totalExtraPoints =  _.reduce(extraPoints, (acc, num) -> acc + num)

            # Add them to current sprint
            $scope.sprints[0].user_stories = _.union(selectedUss, $scope.sprints[0].user_stories)
            # Update the total of points
            $scope.sprints[0].total_points += totalExtraPoints

            $ctrl.filterVisibleUserstories()
            $repo.saveAll(selectedUss)

            scopeDefer $scope, ->
                $scope.$broadcast("doomline:redraw")

        # Enable move to current sprint only when there are selected us's
        $el.on "change", ".backlog-table-body .user-stories input:checkbox", (event) ->
            moveToCurrentSprintDom = $el.find("#move-to-current-sprint")
            selectedUsDom = $el.find(".backlog-table-body .user-stories input:checkbox:checked")

            if selectedUsDom.length > 0 and $scope.sprints.length > 0
                moveToCurrentSprintDom.show()
            else
                moveToCurrentSprintDom.hide()

        $el.on "click", "#move-to-current-sprint", (event) =>
            # Calculating the us's to be modified
            ussDom = $el.find(".backlog-table-body .user-stories input:checkbox:checked")

            ussToMove = _.map ussDom, (item) ->
                itemScope = angular.element(item).scope()
                itemScope.us.milestone = $scope.sprints[0].id
                return itemScope.us

            $scope.$apply(_.partial(moveToCurrentSprint, ussToMove))

        $el.on "click", "#show-tags", (event) ->
            event.preventDefault()
            target = angular.element(event.currentTarget)
            $el.find(".user-story-tags").toggle()
            target.toggleClass("active")
            toggleText(target.find(".text"), ["Hide Tags", "Show Tags"]) # TODO: i18n


    #########################
    ## Filters Link
    #########################

    linkFilters = ($scope, $el, $attrs, $ctrl) ->
        $scope.filtersSearch = {}
        $el.on "click", "#show-filters-button", (event) ->
            event.preventDefault()
            target = angular.element(event.currentTarget)
            $el.find("sidebar.filters-bar").toggleClass("active")
            target.toggleClass("active")
            toggleText(target.find(".text"), ["Hide Filters", "Show Filters"]) # TODO: i18n
            $rootscope.$broadcast("resize")

        $el.on "click", "section.filters a.single-filter", (event) ->
            event.preventDefault()
            target = angular.element(event.currentTarget)
            targetScope = target.scope()

            $scope.$apply ->
                targetScope.tag.selected = not (targetScope.tag.selected or false)
                $ctrl.filterVisibleUserstories()

    link = ($scope, $el, $attrs, $rootscope) ->
        $ctrl = $el.controller()

        linkToolbar($scope, $el, $attrs, $ctrl)
        linkSortable($scope, $el, $attrs, $ctrl)
        linkFilters($scope, $el, $attrs, $ctrl)
        linkDoomLine($scope, $el, $attrs, $ctrl)

        $scope.$on "$destroy", ->
            $el.off()

    return {link: link}

#############################################################################
## Sprint Directive
#############################################################################

BacklogSprintDirective = ($repo) ->

    #########################
    ## Common parts
    #########################

    linkCommon = ($scope, $el, $attrs, $ctrl) ->
        sprint = $scope.$eval($attrs.tgBacklogSprint)
        if $scope.$first
            $el.addClass("sprint-current")
            $el.find(".sprint-table").addClass('open')

        else if sprint.closed
            $el.addClass("sprint-closed")

        else if not $scope.$first and not sprint.closed
            $el.addClass("sprint-old-open")

        # Update progress bars
        progressPercentage = Math.round(100 * (sprint.closed_points / sprint.total_points))
        $el.find(".current-progress").css("width", "#{progressPercentage}%")

        # Event Handlers
        $el.on "click", ".sprint-name > .icon-arrow-up", (event) ->
            target = $(event.currentTarget)
            target.toggleClass('active')
            $el.find(".sprint-table").toggleClass('open')

    #########################
    ## Drag & Drop Link
    #########################

    linkSortable = ($scope, $el, $attrs, $ctrl) ->
        resortAndSave = ->
            toSave = []
            for item, i in $scope.sprint.user_stories
                if item.order == i
                    continue
                item.order = i

            toSave = _.filter($scope.sprint.user_stories, (x) -> x.isModified())
            $repo.saveAll(toSave).then ->
                console.log "FINISHED", arguments

        onUpdateItem = (event) ->
            item = angular.element(event.item)
            itemScope = item.scope()

            ids = _.map($scope.sprint.user_stories, {"id": itemScope.us.id})
            index = ids.indexOf(itemScope.us.id)

            $scope.sprint.user_stories.splice(index, 1)
            $scope.sprint.user_stories.splice(item.index(), 0, itemScope.us)
            resortAndSave()

        onAddItem = (event) ->
            item = angular.element(event.item)
            itemScope = item.scope()
            itemIndex = item.index()

            itemScope.us.milestone = $scope.sprint.id
            userstories = $scope.sprint.user_stories
            userstories.splice(itemIndex, 0, itemScope.us)

            item.remove()
            item.off()

            $scope.$apply()
            resortAndSave()

        onRemoveItem = (event) ->
            item = angular.element(event.item)
            itemScope = item.scope()

            ids = _.map($scope.sprint.user_stories, "id")
            index = ids.indexOf(itemScope.us.id)

            if index != -1
                userstories = $scope.sprint.user_stories
                userstories.splice(index, 1)

            item.off()
            itemScope.$destroy()

        dom = $el.find(".sprint-table")

        sortable = new Sortable(dom[0], {
            group: "backlog",
            selector: ".milestone-us-item-row",
            onUpdate: onUpdateItem,
            onAdd: onAddItem,
            onRemove: onRemoveItem,
        })

    link = ($scope, $el, $attrs) ->
        $ctrl = $el.closest("div.wrapper").controller()
        linkSortable($scope, $el, $attrs, $ctrl)
        linkCommon($scope, $el, $attrs, $ctrl)

        $scope.$on "$destroy", ->
            $el.off()

    return {link: link}


#############################################################################
## User story points directive
#############################################################################

UsRolePointsSelectorDirective = ($rootscope) ->
    #TODO: i18n
    selectionTemplate = _.template("""
      <ul class="popover pop-role">
          <li><a class="clear-selection" href="" title="All">All</a></li>
          <% _.each(roles, function(role) { %>
          <li><a href="" class="role" title="<%- role.name %>"
                 data-role-id="<%- role.id %>"><%- role.name %></a></li>
          <% }); %>
      </ul>
    """)

    link = ($scope, $el, $attrs) ->
        # Watchers
        bindOnce $scope, "project", (project) ->
            roles = _.filter(project.roles, "computable")
            $el.append(selectionTemplate({ 'roles':  roles }))

        $scope.$on "uspoints:select", (ctx, roleId, roleName) ->
            $el.find(".popover").hide()
            $el.find(".header-points").text(roleName)

        $scope.$on "uspoints:clear-selection", (ctx, roleId) ->
            $el.find(".popover").hide()
            $el.find(".header-points").text("Points") #TODO: i18n

        # Dom Event Handlers
        $el.on "click", (event) ->
            target = angular.element(event.target)

            if target.is("span") or target.is("div")
                event.stopPropagation()

            $el.find(".popover").show()
            body = angular.element("body")
            body.one "click", (event) ->
                $el.find(".popover").hide()

        $el.on "click", ".clear-selection", (event) ->
            event.preventDefault()
            event.stopPropagation()
            $rootscope.$broadcast("uspoints:clear-selection")

        $el.on "click", ".role", (event) ->
            event.preventDefault()
            event.stopPropagation()

            target = angular.element(event.currentTarget)
            rolScope = target.scope()
            $rootscope.$broadcast("uspoints:select", target.data("role-id"), target.text())

        $scope.$on "$destroy", ->
            $el.off()

    return {link: link}

UsPointsDirective = ($repo) ->
    selectionTemplate = _.template("""
    <ul class="popover pop-role">
        <% _.each(roles, function(role) { %>
        <li><a href="" class="role" title="<%- role.name %>"
               data-role-id="<%- role.id %>"><%- role.name %></a>
        </li>
        <% }); %>
    </ul>
    """)

    pointsTemplate = _.template("""
    <ul class="popover pop-points-open">
        <% _.each(points, function(point) { %>
        <li><a href="" class="point" title="<%- point.name %>"
               data-point-id="<%- point.id %>"><%- point.name %></a>
        </li>
        <% }); %>
    </ul>
    """)

    link = ($scope, $el, $attrs) ->
        $ctrl = $el.controller()

        us = $scope.$eval($attrs.tgUsPoints)
        updatingSelectedRoleId = null
        selectedRoleId = null

        updatePoints = (roleId) ->
            pointsDom = $el.find("a > span.points-value")
            usTotalPoints = calculateTotalPoints(us)
            us.total_points = usTotalPoints
            if not roleId?
                pointsDom.text(us.total_points)
            else
                pointId = us.points[roleId]
                points = $scope.pointsById[pointId]
                pointsDom.text("#{points.name}/#{us.total_points}")

        calculateTotalPoints = ->
            values = _.map(us.points, (v, k) -> $scope.pointsById[v].value)
            values = _.filter(values, (num) -> num?)
            if values.length == 0
                return "?"

            return _.reduce(values, (acc, num) -> acc + num)

        updatePoints(null)

        bindOnce $scope, "project", (project) ->
            roles = _.filter(project.roles, "computable")
            $el.append(selectionTemplate({ "roles":  roles }))
            $el.append(pointsTemplate({ "points":  project.points }))

        $scope.$on "uspoints:select", (ctx, roleId, roleName) ->
            updatePoints(roleId)
            selectedRoleId = roleId

        $scope.$on "uspoints:clear-selection", (ctx) ->
            updatePoints(null)
            selectedRoleId = null

        $el.on "click", "a.us-points", (event) ->
            event.preventDefault()
            target = angular.element(event.target)

            if target.is("span")
                event.stopPropagation()

            if selectedRoleId?
                updatingSelectedRoleId = selectedRoleId
                $el.find(".pop-points-open").show()
            else
                $el.find(".pop-role").show()

            body = angular.element("body")
            body.one "click", (event) ->
                $el.find(".popover").hide()

        $el.on "click", ".role", (event) ->
            event.preventDefault()
            event.stopPropagation()

            target = angular.element(event.currentTarget)
            updatingSelectedRoleId = target.data("role-id")

            $el.find(".pop-points-open").show()
            $el.find(".pop-role").hide()

        $el.on "click", ".point", (event) ->
            event.preventDefault()
            event.stopPropagation()

            target = angular.element(event.currentTarget)
            $el.find(".pop-points-open").hide()

            $scope.$apply () ->
                usPoints = _.clone(us.points, true)
                usPoints[updatingSelectedRoleId] = target.data("point-id")
                us.points = usPoints

                usTotalPoints = calculateTotalPoints(us)
                us.total_points = usTotalPoints

                updatePoints(selectedRoleId)

                $repo.save(us).then ->
                    # Little Hack for refresh.
                    $repo.refresh(us).then ->
                        $ctrl.loadProjectStats()

                scopeDefer $scope, ->
                    $scope.$emit("doomline:redraw")

        $scope.$on "$destroy", ->
            $el.off()

    return {link: link}


#############################################################################
## Burndown graph directive
#############################################################################

GmBacklogGraphDirective = ->
    redrawChart = (element, dataToDraw) ->
        width = element.width()
        element.height(width/6)
        milestones = _.map(dataToDraw.milestones, (ml) -> ml.name)
        milestonesRange = [0..(milestones.length - 1)]
        data = []
        zero_line = _.map(dataToDraw.milestones, (ml) -> 0)
        data.push({
            data: _.zip(milestonesRange, zero_line)
            lines:
                fillColor : "rgba(0,0,0,0)"
            points:
                show: false
        })
        optimal_line = _.map(dataToDraw.milestones, (ml) -> ml.optimal)
        data.push({
            data: _.zip(milestonesRange, optimal_line)
            lines:
                fillColor : "rgba(120,120,120,0.2)"
        })
        evolution_line = _.filter(_.map(dataToDraw.milestones, (ml) -> ml.evolution), (evolution) -> evolution?)
        data.push({
            data: _.zip(milestonesRange, evolution_line)
            lines:
                fillColor : "rgba(102,153,51,0.3)"
        })
        team_increment_line = _.map(dataToDraw.milestones, (ml) -> -ml['team-increment'])
        data.push({
            data: _.zip(milestonesRange, team_increment_line)
            lines:
                fillColor : "rgba(153,51,51,0.3)"
        })
        client_increment_line = _.map(dataToDraw.milestones, (ml) -> -ml['team-increment']-ml['client-increment'])
        data.push({
            data: _.zip(milestonesRange, client_increment_line)
            lines:
                fillColor : "rgba(255,51,51,0.3)"
        })

        colors = [
            "rgba(0,0,0,1)"
            "rgba(120,120,120,0.2)"
            "rgba(102,153,51,1)"
            "rgba(153,51,51,1)"
            "rgba(255,51,51,1)"
        ]

        options = {
            grid: {
                borderWidth: { top: 0, right: 1, left:0, bottom: 0 }
                borderColor: '#ccc'
            }
            xaxis: {
                ticks: _.zip(milestonesRange, milestones)
                axisLabelUseCanvas: true
                axisLabelFontSizePixels: 12
                axisLabelFontFamily: 'Verdana, Arial, Helvetica, Tahoma, sans-serif'
                axisLabelPadding: 5
            }
            series: {
                shadowSize: 0
                lines: {
                    show: true
                    fill: true
                }
                points: {
                    show: true
                    fill: true
                    radius: 4
                    lineWidth: 2
                }
            }
            colors: colors
        }

        element.empty()
        element.plot(data, options).data("plot")

    link = ($scope, $el, $attrs) ->
        element = angular.element($el)

        $scope.$watch 'stats', (value) ->
            if $scope.stats?
                redrawChart(element, $scope.stats)

                $scope.$on "resize", ->
                    redrawChart(element, $scope.stats)

        $scope.$on "$destroy", ->
            $el.off()

    return {link: link}


module.directive("tgBacklog", ["$tgRepo", "$rootScope", BacklogDirective])
module.directive("tgBacklogSprint", ["$tgRepo", BacklogSprintDirective])
module.directive("tgUsPoints", ["$tgRepo", UsPointsDirective])
module.directive("tgUsRolePointsSelector", ["$rootScope", UsRolePointsSelectorDirective])
module.directive("tgGmBacklogGraph", GmBacklogGraphDirective)

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
# File: modules/issues.coffee
###

taiga = @.taiga

mixOf = @.taiga.mixOf
trim = @.taiga.trim
toString = @.taiga.toString
joinStr = @.taiga.joinStr
groupBy = @.taiga.groupBy
bindOnce = @.taiga.bindOnce

module = angular.module("taigaIssues")

#############################################################################
## Issues Controller
#############################################################################

class IssuesController extends mixOf(taiga.Controller, taiga.PageMixin, taiga.FiltersMixin)
    @.$inject = [
        "$scope",
        "$rootScope",
        "$tgRepo",
        "$tgConfirm",
        "$tgResources",
        "$routeParams",
        "$q",
        "$location"
    ]

    constructor: (@scope, @rootscope, @repo, @confirm, @rs, @params, @q, @location) ->
        @scope.sprintId = @params.id
        @scope.sectionName = "Issues"

        promise = @.loadInitialData()
        promise.then null, ->
            console.log "FAIL" #TODO

    loadFilters: ->
        defered = @q.defer()
        defered.resolve()
        return defered.promise

    loadProject: ->
        return @rs.projects.get(@scope.projectId).then (project) =>
            @scope.project = project
            @scope.issueStatusById = groupBy(project.issue_statuses, (x) -> x.id)
            @scope.severityById = groupBy(project.severities, (x) -> x.id)
            @scope.priorityById = groupBy(project.priorities, (x) -> x.id)
            @scope.membersById = groupBy(project.memberships, (x) -> x.user)
            return project

    getFilters: ->
        filters = _.pick(@location.search(), "page", "tags", "status", "type")
        filters.page = 1 if not filters.page
        return filters

    loadIssues: ->
        filters = @.getFilters()

        promise = @rs.issues.list(@scope.projectId, filters).then (data) =>
            @scope.issues = data.models
            @scope.page = data.current
            @scope.count = data.count
            @scope.paginatedBy = data.paginatedBy
            return data

        return promise

    loadInitialData: ->
        promise = @repo.resolve({pslug: @params.pslug}).then (data) =>
            @scope.projectId = data.project
            return data

        return promise.then(=> @.loadProject())
                      .then(=> @.loadUsersAndRoles())
                      .then(=> @.loadFilters())
                      .then(=> @.loadIssues())

module.controller("IssuesController", IssuesController)

#############################################################################
## Issues Directive
#############################################################################

paginatorTemplate = """
<ul class="paginator">
    <% if (showPrevious) { %>
    <li class="previous">
        <a href="" class="previous next_prev_button" class="disabled">
            <span i18next="pagination.prev">Prev</span>
        </a>
    </li>
    <% } %>

    <% _.each(pages, function(item) { %>
    <li class="<%= item.classes %>">
        <% if (item.type === "page") { %>
        <a href="" data-pagenum="<%= item.num %>"><%= item.num %></a>
        <% } else if (item.type === "page-active") { %>
        <span class="active"><%= item.num %></span>
        <% } else { %>
        <span>...</span>
        <% } %>
    </li>
    <% }); %>

    <% if (showNext) { %>
    <li class="next">
        <a href="" class="next next_prev_button" class="disabled">
            <span i18next="pagination.next">Next</span>
        </a>
    </li>
    <% } %>
</ul>
"""

IssuesDirective = ($log, $location) ->

    #########################
    ## Issues Pagination
    #########################

    template = _.template(paginatorTemplate)

    linkPagination = ($scope, $el, $attrs, $ctrl) ->
        # Constants
        afterCurrent = 5
        beforeCurrent = 5
        atBegin = 2
        atEnd = 2

        $pagEl = $el.find("section.issues-paginator")

        getNumPages = ->
            numPages = $scope.count / $scope.paginatedBy
            if parseInt(numPages, 10) < numPages
                numPages = parseInt(numPages, 10) + 1
            else
                numPages = parseInt(numPages, 10)

            return numPages

        renderPagination = ->
            numPages = getNumPages()

            if numPages <= 1
                $pagEl.hide()
                return

            pages = []
            options = {}
            options.pages = pages
            options.showPrevious = ($scope.page > 1)
            options.showNext = not ($scope.page == numPages)

            cpage = $scope.page

            for i in [1..numPages]
                if i == (cpage + afterCurrent) and numPages > (cpage + afterCurrent + atEnd)
                    pages.push({classes: "dots", type: "dots"})
                else if i == (cpage - beforeCurrent) and cpage > (atBegin + beforeCurrent)
                    pages.push({classes: "dots", type: "dots"})
                else if i > (cpage + afterCurrent) and i <= (numPages - atEnd)
                else if i < (cpage - beforeCurrent) and i > atBegin
                else if i == cpage
                    pages.push({classes: "active", num: i, type: "page-active"})
                else
                    pages.push({classes: "page", num: i, type: "page"})

            $pagEl.html(template(options))

        $scope.$watch "issues", (value) ->
            # Do nothing if value is not logical true
            return if not value

            renderPagination()

        $el.on "click", ".issues-paginator a.next", (event) ->
            event.preventDefault()

            $scope.$apply ->
                $ctrl.selectFilter("page", $scope.page + 1)
                $ctrl.loadIssues()

        $el.on "click", ".issues-paginator a.previous", (event) ->
            event.preventDefault()
            $scope.$apply ->
                $ctrl.selectFilter("page", $scope.page - 1)
                $ctrl.loadIssues()

        $el.on "click", ".issues-paginator li.page > a", (event) ->
            event.preventDefault()
            target = angular.element(event.currentTarget)
            pagenum = target.data("pagenum")

            $scope.$apply ->
                $ctrl.selectFilter("page", pagenum)
                $ctrl.loadIssues()

    #########################
    ## Issues Filters
    #########################

    linkFilters = ($scope, $el, $attrs, $ctrl) ->
        $log.debug "IssuesDirective:linkFilters"

    #########################
    ## Issues Link
    #########################

    link = ($scope, $el, $attrs) ->
        $ctrl = $el.controller()
        linkFilters($scope, $el, $attrs, $ctrl)
        linkPagination($scope, $el, $attrs, $ctrl)

    return {link:link}


IssueStatusDirective = ->
    link = ($scope, $el, $attrs) ->
        issue = $scope.$eval($attrs.tgIssueStatus)
        bindOnce $scope, "issueStatusById", (issueStatusById) ->
            $el.html(issueStatusById[issue.status].name)

    return {link:link}


IssueAssignedtoDirective = ->
    template = """
    <figure class="avatar">
        <img src="http://thecodeplayer.com/u/uifaces/12.jpg" alt="username"/>
        <figcaption>--</figcaption>
    </figure>
    """

    link = ($scope, $el, $attrs) ->
        issue = $scope.$eval($attrs.tgIssueAssignedto)
        if issue.assigned_to is null
            $el.find("figcaption").html("Unassigned")
        else
            bindOnce $scope, "membersById", (membersById) ->
                memberName = membersById[issue.assigned_to].full_name_display
                $el.find("figcaption").html(memberName)

    return {
        template: template
        link:link
    }


IssuePriorityDirective = ->
    template = """
    <div class="level"></div>
    """

    link = ($scope, $el, $attrs) ->
        issue = $scope.$eval($attrs.tgIssuePriority)
        bindOnce $scope, "priorityById", (priorityById) ->
            priority = priorityById[issue.priority]

            domNode = $el.find("div.level")
            domNode.css("background-color", priority.color)
            domNode.addClass(priority.name.toLowerCase())
            domNode.attr("title", priority.name)

    return {
        link: link
        template: template
    }


IssueSeverityDirective = ->
    template = """
    <div class="level"></div>
    """

    link = ($scope, $el, $attrs) ->
        issue = $scope.$eval($attrs.tgIssueSeverity)
        bindOnce $scope, "severityById", (severityById) ->
            severity = severityById[issue.severity]

            domNode = $el.find("div.level")
            domNode.css("background-color", severity.color)
            domNode.addClass(severity.name.toLowerCase())
            domNode.attr("title", severity.name)

    return {
        link: link
        template: template
    }


module.directive("tgIssues", ["$log", "$tgLocation", IssuesDirective])
module.directive("tgIssueStatus", IssueStatusDirective)
module.directive("tgIssueAssignedto", IssueAssignedtoDirective)
module.directive("tgIssuePriority", IssuePriorityDirective)
module.directive("tgIssueSeverity", IssueSeverityDirective)

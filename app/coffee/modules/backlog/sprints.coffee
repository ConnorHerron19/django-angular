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
# File: modules/backlog/sprints.coffee
###

taiga = @.taiga

module = angular.module("taigaBacklog")


#############################################################################
## Sprint Actions Directive
#############################################################################

BacklogSprintDirective = ($repo, $rootscope) ->
    sprintTableMinHeight = 50
    slideOptions = {
        duration: 500,
        easing: 'linear'
    }

    refreshSprintTableHeight = (sprintTable) =>
        if !sprintTable.find(".row").length
            sprintTable.css("height", sprintTableMinHeight)
        else
            sprintTable.css("height", "auto")

    toggleSprint = ($el) =>
        sprintTable = $el.find(".sprint-table")
        sprintArrow = $el.find(".icon-arrow-up")

        sprintArrow.toggleClass('active')
        sprintTable.toggleClass('open')

        refreshSprintTableHeight(sprintTable)

    link = ($scope, $el, $attrs) ->
        $scope.$watch $attrs.tgBacklogSprint, (sprint) ->
            sprint = $scope.$eval($attrs.tgBacklogSprint)

            if sprint.closed
                $el.addClass("sprint-closed")
            else
                toggleSprint($el)

        # Event Handlers
        $el.on "click", ".sprint-name > .icon-arrow-up", (event) ->
            event.preventDefault()

            toggleSprint($el)

            $el.find(".sprint-table").slideToggle(slideOptions)

        $el.on "click", ".sprint-name > .icon-edit", (event) ->
            event.preventDefault()

            sprint = $scope.$eval($attrs.tgBacklogSprint)
            $rootscope.$broadcast("sprintform:edit", sprint)

        $scope.$on "$destroy", ->
            $el.off()

    return {link: link}

module.directive("tgBacklogSprint", ["$tgRepo", "$rootScope", BacklogSprintDirective])


#############################################################################
## Sprint Header Directive
#############################################################################

BacklogSprintHeaderDirective = ($navUrls, $template, $compile) ->
    template = $template.get("backlog/sprint-header.html")

    link = ($scope, $el, $attrs, $model) ->
        isEditable = ->
            return $scope.project.my_permissions.indexOf("modify_milestone") != -1

        isVisible = ->
            return $scope.project.my_permissions.indexOf("view_milestones") != -1

        render = (sprint) ->
            taskboardUrl = $navUrls.resolve("project-taskboard",
                                            {project: $scope.project.slug, sprint: sprint.slug})

            start = moment(sprint.estimated_start).format("DD MMM YYYY")
            finish = moment(sprint.estimated_finish).format("DD MMM YYYY")
            estimatedDateRange = "#{start}-#{finish}"

            ctx = {
                name: sprint.name
                taskboardUrl: taskboardUrl
                estimatedDateRange: estimatedDateRange
                closedPoints: sprint.closed_points or 0
                totalPoints: sprint.total_points or 0
                isVisible: isVisible()
                isEditable: isEditable()
            }

            templateScope = $scope.$new()

            _.assign(templateScope, ctx)

            compiledTemplate = $compile(template)(templateScope)
            $el.html(compiledTemplate)

        $scope.$watch $attrs.ngModel, (sprint) ->
            render(sprint)

        $scope.$on "sprintform:edit:success", ->
            render($model.$modelValue)

        $scope.$on "$destroy", ->
            $el.off()

    return {
        link: link
        restrict: "EA"
        require: "ngModel"
    }

module.directive("tgBacklogSprintHeader", ["$tgNavUrls", "$tgTemplate", "$compile", BacklogSprintHeaderDirective])

#############################################################################
## Toggle Closed Sprints Directive
#############################################################################

ToggleExcludeClosedSprintsVisualization = ($rootscope, $loading, $translate) ->
    excludeClosedSprints = true

    link = ($scope, $el, $attrs) ->
        # insert loading wrapper
        loadingElm = $("<div>")
        $el.after(loadingElm)

        # Event Handlers
        $el.on "click", (event) ->
            event.preventDefault()
            excludeClosedSprints  = not excludeClosedSprints

            $loading.start(loadingElm)

            if excludeClosedSprints
                $rootscope.$broadcast("backlog:unload-closed-sprints")
            else
                $rootscope.$broadcast("backlog:load-closed-sprints")

        $scope.$on "$destroy", ->
            $el.off()

        $scope.$on "closed-sprints:reloaded", (ctx, sprints) =>
            $loading.finish(loadingElm)

            if sprints.length > 0
                key = "BACKLOG.SPRINTS.ACTION_HIDE_CLOSED_SPRINTS"
            else
                key = "BACKLOG.SPRINTS.ACTION_SHOW_CLOSED_SPRINTS"

            text = $translate.instant(key)

            $el.find(".text").text(text)

    return {link: link}

module.directive("tgBacklogToggleClosedSprintsVisualization", ["$rootScope", "$tgLoading", "$translate", ToggleExcludeClosedSprintsVisualization])

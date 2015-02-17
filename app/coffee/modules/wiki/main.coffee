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
# File: modules/wiki/detail.coffee
###

taiga = @.taiga

mixOf = @.taiga.mixOf
groupBy = @.taiga.groupBy
bindOnce = @.taiga.bindOnce
unslugify = @.taiga.unslugify
debounce = @.taiga.debounce

module = angular.module("taigaWiki")

#############################################################################
## Wiki Detail Controller
#############################################################################

class WikiDetailController extends mixOf(taiga.Controller, taiga.PageMixin)
    @.$inject = [
        "$scope",
        "$rootScope",
        "$tgRepo",
        "$tgModel",
        "$tgConfirm",
        "$tgResources",
        "$routeParams",
        "$q",
        "$tgLocation",
        "$filter",
        "$log",
        "$appTitle",
        "$tgNavUrls",
        "$tgAnalytics",
        "tgLoader"
    ]

    constructor: (@scope, @rootscope, @repo, @model, @confirm, @rs, @params, @q, @location,
                  @filter, @log, @appTitle, @navUrls, @analytics, tgLoader) ->
        @scope.projectSlug = @params.pslug
        @scope.wikiSlug = @params.slug
        @scope.sectionName = "Wiki"

        promise = @.loadInitialData()

        # On Success
        promise.then () =>
            @appTitle.set("Wiki - " + @scope.project.name)

        # On Error
        promise.then null, @.onInitialDataError.bind(@)
        promise.finally tgLoader.pageLoaded

    loadProject: ->
        return @rs.projects.getBySlug(@params.pslug).then (project) =>
            @scope.projectId = project.id
            @scope.project = project
            @scope.$emit('project:loaded', project)
            @scope.membersById = groupBy(project.memberships, (x) -> x.user)
            return project

    loadWiki: ->
        promise = @rs.wiki.getBySlug(@scope.projectId, @params.slug)
        promise.then (wiki) =>
            @scope.wiki = wiki
            @scope.wikiId = wiki.id
            return @scope.wiki

        promise.then null, (xhr) =>
            @scope.wikiId = null

            if @scope.project.my_permissions.indexOf("add_wiki_page") == -1
                return null

            data = {
                project: @scope.projectId
                slug: @scope.wikiSlug
                content: ""
            }
            @scope.wiki = @model.make_model("wiki", data)
            return @scope.wiki

    loadWikiLinks: ->
        return @rs.wiki.listLinks(@scope.projectId).then (wikiLinks) =>
            @scope.wikiLinks = wikiLinks

    loadInitialData: ->
        promise = @.loadProject()
        return promise.then (project) =>
            @.fillUsersAndRoles(project.users, project.roles)
            @q.all([@.loadWikiLinks(), @.loadWiki()])

    delete: ->
        # TODO: i18n
        title = "Delete Wiki Page"
        message = unslugify(@scope.wiki.slug)

        @confirm.askOnDelete(title, message).then (finish) =>
            onSuccess = =>
                finish()
                ctx = {project: @scope.projectSlug}
                @location.path(@navUrls.resolve("project-wiki", ctx))
                @confirm.notify("success")

            onError = =>
                finish(false)
                @confirm.notify("error")

            @repo.remove(@scope.wiki).then onSuccess, onError

module.controller("WikiDetailController", WikiDetailController)


#############################################################################
## Wiki Summary Directive
#############################################################################

WikiSummaryDirective = ($log, $template) ->
    template = $template.get("wiki/wiki-summary.html", true)

    link = ($scope, $el, $attrs, $model) ->
        render = (wiki) ->
            if not $scope.usersById?
                $log.error "WikiSummaryDirective requires userById set in scope."
            else
                user = $scope.usersById[wiki.last_modifier]

            if user is undefined
                user = {name: "unknown", imgUrl: "/images/unnamed.png"}
            else
                user = {name: user.full_name_display, imgUrl: user.photo}

            ctx = {
                totalEditions: wiki.editions
                lastModifiedDate: moment(wiki.modified_date).format("DD MMM YYYY HH:mm")
                user: user
            }
            html = template(ctx)
            $el.html(html)

        $scope.$watch $attrs.ngModel, (wikiPage) ->
            return if not wikiPage
            render(wikiPage)

        $scope.$on "wiki:edit", (event, wikiPage) ->
            render(wikiPage)

        $scope.$on "$destroy", ->
            $el.off()

    return {
        link: link
        restrict: "EA"
        require: "ngModel"
    }

module.directive("tgWikiSummary", ["$log", "$tgTemplate", WikiSummaryDirective])


#############################################################################
## Editable Wiki Content Directive
#############################################################################

EditableWikiContentDirective = ($window, $document, $repo, $confirm, $loading, $analytics, $qqueue) ->
    link = ($scope, $el, $attrs, $model) ->
        isEditable = ->
            return $scope.project.my_permissions.indexOf("modify_wiki_page") != -1

        switchToEditMode = ->
            $el.find('.edit-wiki-content').show()
            $el.find('.view-wiki-content').hide()
            $el.find('textarea').focus()

        switchToReadMode = ->
            $el.find('.edit-wiki-content').hide()
            $el.find('.view-wiki-content').show()

        disableEdition = ->
            $el.find(".view-wiki-content .edit").remove()
            $el.find(".edit-wiki-content").remove()

        cancelEdition = ->
            return if not $model.$modelValue.id

            $scope.$apply () =>
                $model.$modelValue.revert()
            switchToReadMode()

        getSelectedText = ->
            if $window.getSelection
                return $window.getSelection().toString()
            else if $document.selection
                return $document.selection.createRange().text
            return null

        save = $qqueue.bindAdd (wiki) ->
            onSuccess = (wikiPage) ->
                if not wiki.id?
                    $analytics.trackEvent("wikipage", "create", "create wiki page", 1)

                $model.$modelValue = wikiPage
                $scope.$broadcast("wiki:edit", wikiPage)

                $confirm.notify("success")
                switchToReadMode()

            onError = ->
                $confirm.notify("error")

            $loading.start($el.find('.save-container'))

            if wiki.id?
                promise = $repo.save(wiki).then(onSuccess, onError)
            else
                promise = $repo.create("wiki", wiki).then(onSuccess, onError)

            promise.finally ->
                $loading.finish($el.find('.save-container'))

        $el.on "mousedown", ".view-wiki-content", (event) ->
            target = angular.element(event.target)
            return if not isEditable()
            return if event.button == 2

        $el.on "mouseup", ".view-wiki-content", (event) ->
            target = angular.element(event.target)
            return if getSelectedText()
            return if target.is('a')
            return if target.is('pre')

            switchToEditMode()

        $el.on "click", ".save", debounce 2000, ->
            save($scope.wiki)

        $el.on "click", ".cancel", ->
            cancelEdition()

        $el.on "keydown", "textarea", (event) ->
            if event.keyCode == 27
                cancelEdition()

        $scope.$watch $attrs.ngModel, (wikiPage) ->
            return if not wikiPage

            if isEditable()
                $el.addClass('editable')
                if not wikiPage.id?
                    switchToEditMode()
            else
                disableEdition()

        $scope.$on "$destroy", ->
            $el.off()

    return {
        link: link
        restrict: "EA"
        require: "ngModel"
        templateUrl: "wiki/editable-wiki-content.html"
    }

module.directive("tgEditableWikiContent", ["$window", "$document", "$tgRepo", "$tgConfirm", "$tgLoading",
                                           "$tgAnalytics", "$tgQqueue", EditableWikiContentDirective])

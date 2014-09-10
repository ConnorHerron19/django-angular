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
# File: modules/common/attachments.coffee
###

taiga = @.taiga
sizeFormat = @.taiga.sizeFormat
bindOnce = @.taiga.bindOnce

module = angular.module("taigaCommon")


class AttachmentsController extends taiga.Controller
    @.$inject = ["$scope", "$rootScope", "$tgRepo", "$tgResources", "$tgConfirm", "$q"]

    constructor: (@scope, @rootscope, @repo, @rs, @confirm, @q) ->
        _.bindAll(@)
        @.type = null
        @.objectId = null

        @.uploadingAttachments = []
        @.attachments = []
        @.attachmentsCount = 0
        @.deprecatedAttachmentsCount = 0
        @.showDeprecated = false

    initialize: (type, objectId) ->
        @.type = type
        @.objectId = objectId

    loadAttachments: ->
        urlname = "attachments/#{@.type}"
        id = @.objectId

        return @rs.attachments.list(urlname, id).then (attachments) =>
            @.attachments = _.sortBy(attachments, "order")
            @.updateCounters()
            return attachments

    updateCounters: ->
        @.attachmentsCount = @.attachments.length
        @.deprecatedAttachmentsCount = _.filter(@.attachments, {is_deprecated: true}).length

    _createAttachment: (attachment) ->
        projectId = @scope.projectId
        urlName = "attachments/#{@.type}"

        promise = @rs.attachments.create(urlName, projectId, @.objectId, attachment)
        promise = promise.then (data) =>
            data.isCreatedRightNow = true

            index = @.uploadingAttachments.indexOf(attachment)
            @.uploadingAttachments.splice(index, 1)
            @.attachments.push(data)
            @rootscope.$broadcast("attachment:create")

        promise = promise.then null, (data) ->
            index = @.uploadingAttachments.indexOf(attachment)
            @.uploadingAttachments.splice(index, 1)
            @confirm.notify("error", null, "We have not been able to upload '#{attachment.name}'.")
            return @q.reject(data)

        return promise

    # Create attachments in bulk
    createAttachments: (attachments) ->
        promises = _.map(attachments, (x) => @._createAttachment(x))
        return @q.all.apply(null, promises).then =>
            @.updateCounters()

    # Add uploading attachment tracking.
    addUploadingAttachments: (attachments) ->
        @.uploadingAttachments = _.union(@.uploadingAttachments, attachments)

    # Change order of attachment in a ordered list.
    # This function is mainly executed after sortable ends.
    reorderAttachment: (attachment, newIndex) ->
        oldIndex = @.attachments.indexOf(attachment)
        return if oldIndex == newIndex

        @.attachments.splice(oldIndex, 1)
        @.attachments.splice(newIndex, 0, attachment)

        _.each(@.attachments, (x,i) -> x.order = i+1)

    # Persist one concrete attachment.
    # This function is mainly used when user clicks
    # to save button for save one unique attachment.
    updateAttachment: (attachment) ->
        onSuccess = =>
            @.updateCounters()
            @rootscope.$broadcast("attachment:edit")

        onError = =>
            @confirm.notify("error")
            return @q.reject()

        return @repo.save(attachment).then(onSuccess, onError)

    # Persist all pending modifications on attachments.
    # This function is used mainly for persist the order
    # after sorting.
    saveAttachments: ->
        return @repo.saveAll(@.attachments).then null, =>
            for item in @.attachments
                item.revert()
            @.attachments = _.sorBy(@.attachments, "order")

    # Remove one concrete attachment.
    removeAttachment: (attachment) ->
        title = "Delete attachment"  #TODO: i18in
        subtitle = "the attachment '#{attachment.name}'" #TODO: i18in

        onSuccess = =>
            index = @.attachments.indexOf(attachment)
            @.attachments.splice(index, 1)
            @.updateCounters()
            @rootscope.$broadcast("attachment:delete")

        onError = =>
            @confirm.notify("error", null, "We have not been able to delete #{subtitle}.")
            return @q.reject()

        return @confirm.ask(title, subtitle).then =>
            return @repo.remove(attachment).then(onSuccess, onError)

    # Function used in template for filter visible attachments
    filterAttachments: (item) ->
        if @.showDeprecated
            return true
        return not item.is_deprecated


AttachmentsDirective = ($confirm) ->
    template = _.template("""
    <section class="attachments">
        <div class="attachments-header">
            <h3 class="attachments-title">
                <span class="icon icon-attachments"></span>
                <span class="attachments-num" tg-bind-html="ctrl.attachmentsCount"></span>
                <span class="attachments-text">attachments</span>

                <div tg-check-permission="modify_<%- type %>"
                    title="Add new attachment" class="button button-gray add-attach">
                    <span>+new file</span>
                    <input type="file" multiple="multiple"/>
                </div>
            </h3>
        </div>

        <div class="attachment-body sortable">
            <div ng-repeat="attach in ctrl.attachments|filter:ctrl.filterAttachments track by attach.id"
                tg-attachment="attach"
                class="single-attachment">
            </div>

            <div ng-repeat="file in ctrl.uploadingAttachments" class="single-attachment">
                <div class="attachment-name">
                    <a href="" tg-bo-title="file.name" tg-bo-bind="file.name"></a>
                </div>
                <div class="attachment-size">
                    <span tg-bo-bind="file.size" class="attachment-size"></span>
                </div>
                <div class="attachment-comments">
                    <span ng-bind="file.progressMessage"></span>
                    <div ng-style="{'width': file.progressPercent}" class="percentage"></div>
                </div>
            </div>

            <a href="" title="show deprecated atachments" class="more-attachments"
                ng-if="ctrl.deprecatedAttachmentsCount > 0">
                <span class="text" data-type="show">+ show deprecated atachments</span>
                <span class="text hidden" data-type="hide">- hide deprecated atachments</span>
                <span class="more-attachments-num">
                    ({{ctrl.deprecatedAttachmentsCount }} deprecated)
                </span>
            </a>
        </div>
    </section>""")


    link = ($scope, $el, $attrs, $ctrls) ->
        $ctrl = $ctrls[0]
        $model = $ctrls[1]

        bindOnce $scope, $attrs.ngModel, (value) ->
            $ctrl.initialize($attrs.type, value.id)
            $ctrl.loadAttachments()

        tdom = $el.find("div.attachment-body.sortable")
        tdom.sortable({
            items: "div.single-attachment"
            handle: "a.settings.icon.icon-drag-v"
            dropOnEmpty: true
            revert: 400
            axis: "y"
            placeholder: "sortable-placeholder single-attachment"
        })

        tdom.on "sortstop", (event, ui) ->
            attachment = ui.item.scope().attach
            newIndex = ui.item.index()

            $ctrl.reorderAttachment(attachment, newIndex)
            $ctrl.saveAttachments()

        $el.on "click", "a.add-attach", (event) ->
            event.preventDefault()
            $el.find("input.add-attach").trigger("click")

        $el.on "change", "input.add-attach", (event) ->
            files = _.toArray(event.target.files)
            return if files.length < 1

            $scope.$apply ->
                $ctrl.addUploadingAttachments(files)
                $ctrl.createAttachments(files)

        $el.on "click", ".more-attachments", (event) ->
            event.preventDefault()
            target = angular.element(event.currentTarget)

            $scope.$apply ->
                $ctrl.showDeprecated = not $ctrl.showDeprecated

            target.find("span.text").addClass("hidden")
            if $ctrl.showDeprecated
                target.find("span[data-type=hide]").removeClass("hidden")
                target.find("more-attachments-num").addClass("hidden")
            else
                target.find("span[data-type=show]").removeClass("hidden")
                target.find("more-attachments-num").removeClass("hidden")

        $scope.$on "$destroy", ->
            $el.off()

    templateFn = ($el, $attrs) ->
        return template({type: $attrs.type})

    return {
        require: ["tgAttachments", "ngModel"]
        controller: AttachmentsController
        controllerAs: "ctrl"
        restrict: "AE"
        scope: true
        link: link
        template: templateFn
    }

module.directive("tgAttachments", ["$tgConfirm", AttachmentsDirective])


AttachmentDirective = ->
    template = _.template("""
    <div class="attachment-name">
        <a href="<%- url %>" title="<%- name %>" target="_blank">
            <span class="icon icon-documents"></span>
            <span><%- name %><span>
        </a>
    </div>
    <div class="attachment-size">
        <span><%- size %></span>
    </div>
    <div class="attachment-comments">
        <% if (isDeprecated){ %> <span class="deprecated-file">(deprecated)</span> <% } %>
        <span><%- description %></span>
    </div>
    <% if (modifyPermission) {%>
    <div class="attachment-settings">
        <a class="settings icon icon-edit" href="" title="Edit"></a>
        <a class="settings icon icon-delete" href="" title="Delete"></a>
        <a class="settings icon icon-drag-v" href="" title=""Drag"></a>
    </div>
    <% } %>
    """)

    templateEdit = _.template("""
    <div class="attachment-name">
        <span class="icon.icon-document"></span>
        <a href="<%- url %>" title="<%- name %>" target="_blank"><%- name %></a>
    </div>
    <div class="attachment-size">
        <span><%- size %></span>
    </div>
    <div class="editable editable-attachment-comment">
        <input type="text" name="description" maxlength="140"
               value="<%- description %>""
               placeholder="Type a short description" />
    </div>
    <div class="editable editable-attachment-deprecated">
        <input type="checkbox" name="is-deprecated" id="attach-<%- id %>-is-deprecated"
               <% if (isDeprecated){ %>checked<% } %> />
        <label for="attach-<%- id %>-is-deprecated">Deprecated?</label>
    </div>
    <div class="attachment-settings">
        <a class="editable-settings icon icon-floppy" href="" title="Save"></a>
        <a class="editable-settings icon icon-delete" href="" title="Cancel"></a>
    </div>
    """)

    link = ($scope, $el, $attrs, $ctrl) ->
        render = (attachment, edit=false) ->
            permissions = $scope.project.my_permissions
            modifyPermission = permissions.indexOf("modify_#{$ctrl.type}") > -1

            ctx = {
                id: attachment.id
                name: attachment.name
                url: attachment.url
                size: sizeFormat(attachment.size)
                description: attachment.description
                isDeprecated: attachment.is_deprecated
                modifyPermission: modifyPermission
            }

            if edit
                html = templateEdit(ctx)
            else
                html = template(ctx)

            $el.html(html)
            if attachment.is_deprecated
                $el.addClass("deprecated")

        ## Actions (on edit mode)
        $el.on "click", "a.editable-settings.icon-floppy", (event) ->
            event.preventDefault()

            attachment.description = $el.find("input[name='description']").val()
            attachment.is_deprecated = $el.find("input[name='is-deprecated']").prop("checked")

            $scope.$apply ->
                $ctrl.updateAttachment(attachment).then ->
                    render(attachment)

        $el.on "click", "a.editable-settings.icon-delete", (event) ->
            event.preventDefault()
            render(attachment, false)

        ## Actions (on view mode)
        $el.on "click", "a.settings.icon-edit", (event) ->
            event.preventDefault()
            render(attachment, true)

        $el.on "click", "a.settings.icon-delete", (event) ->
            event.preventDefault()
            $scope.$apply ->
                $ctrl.removeAttachment(attachment)

        $scope.$on "$destroy", ->
            $el.off()

        # Bootstrap
        attachment = $scope.$eval($attrs.tgAttachment)
        render(attachment, attachment.isCreatedRightNow)

    return {
        link: link
        require: "^tgAttachments"
        restrict: "AE"
    }

module.directive("tgAttachment", AttachmentDirective)

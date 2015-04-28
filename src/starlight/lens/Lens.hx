package starlight.lens;

import starlight.lens.VirtualElement.VirtualElementChildren;
import starlight.lens.VirtualElement.VirtualElementAttributes;
import starlight.lens.VirtualElement.VirtualElement;

#if !js
using StringTools;
#end
using VirtualElement.VirtualElementTools;

enum ElementAction {
    RemoveElement;
    AddElement;
    UpdateElement;
    MoveElement;
}

typedef ElementUpdate = {
    action:ElementAction,
    elementId:Int,
    ?tag:String,
    ?attrs:VirtualElementAttributes,
    ?textValue:String,
    ?newParent:Int,
    ?newIndex:Int
}

#if js
    typedef ElementType = js.html.Element;
#else
    typedef ElementType = Dynamic;
#end


class Lens {
    static var elementPropertyAttributes = ['list', 'style', 'form', 'type', 'width', 'height'];
    static var nodeCounter = 0;

    var e = element;  //  A shortcut for easy access in the `view` method.
    var root:ElementType;
    var postProcessing = new haxe.ds.StringMap<Int>();
    public var elementCache = new haxe.ds.IntMap<ElementType>();
    public var currentState = new Array<VirtualElement>();

    public function new() {
#if js
        this.root = js.Browser.document.body;
#end
    };

    /* element is purely a convenience function for helping to create views. */
    public static function element(signature:String, ?attrStruct:Dynamic, ?children:Dynamic):VirtualElement {
        var tagName = 'div';
        var attrs = new VirtualElementAttributes();
        var childArray:VirtualElementChildren = new VirtualElementChildren();

        var classes = new Array<String>();
        var paramChildArray:Array<Dynamic>;

        // Allow the short form of specifying children without attributes.
        switch(Type.typeof(attrStruct)) {
            case TClass(s): {
                switch(Type.getClassName(s)) {
                    case 'String': {
                        paramChildArray = new Array<Dynamic>();
                        paramChildArray.push(attrStruct);
                    }
                    case 'Array': {
                        paramChildArray = cast attrStruct;
                    }
                    default: throw "Invalid Type passed to Lens.element for attributes";
                }
                attrStruct = {};
            }
            case TObject: {
                switch(Type.typeof(children)) {
                    case TClass(s): {
                        switch(Type.getClassName(s)) {
                            case 'String': {
                                paramChildArray = new Array<Dynamic>();
                                paramChildArray.push(children);
                            }
                            case 'Array': {
                                paramChildArray = cast children;
                            }
                            default: throw "Invalid Type passed to Lens.element for children";
                        }
                    }
                    case TNull: paramChildArray = new Array<Dynamic>();
                    default: throw "Invalid Type passed to Lens.element for children";
                }
            }
            case TNull: {
                paramChildArray = new Array<Dynamic>();
                attrStruct = {};
            }
            case TEnum(e): {
                throw 'Elements can\'t set attributes to enum: $e';
            }
            case TFunction: {
                // TODO - This should run the function and reclassify it through this switch statement as a child.
                paramChildArray = new Array<Dynamic>();
                var child = attrStruct();
                switch(Type.getClassName(child)) {
                    case 'String': paramChildArray.push(child);
                    case 'Array': paramChildArray = cast child;
                    default: paramChildArray.push('' + child);
                }
                attrStruct = {};
            }
            default: {
                paramChildArray = new Array<Dynamic>();
                paramChildArray.push('' + attrStruct);
                attrStruct = {};
            }
        }

        var classAttrName = Reflect.hasField(attrStruct, "class") ? "class" : "className";

        var signatureRemaining = signature;
        function smallestPositive(a, b) {
            if (a == b) return 0;
            if (a < 0) a = a*-10000;
            if (b < 0) b = b*-10000;
            if (a > b)
                return 1;
            else
                return -1;
        }
        function getNext(str:String) {
            var indexes = [
                str.indexOf('.'),
                str.indexOf('#'),
                str.indexOf('[')
            ];
            indexes.sort(smallestPositive);
            if (indexes[0] == -1) {
                return str.length;
            }

            return indexes[0];
        }
        var nextElementIndex = getNext(signatureRemaining);

        if (nextElementIndex != 0) {
            tagName = signatureRemaining.substr(0, nextElementIndex).toLowerCase();
            signatureRemaining = signatureRemaining.substr(tagName.length);
            nextElementIndex = getNext(signatureRemaining.substr(1));
        }

        while(signatureRemaining.length != 0) {
            switch(signatureRemaining.charAt(0)) {
                case "#": attrs.set("id", signatureRemaining.substr(1, nextElementIndex));
                case ".": classes.push(signatureRemaining.substr(1, nextElementIndex));
                case "[": {
                    var attrElements = signatureRemaining.substring(1, signatureRemaining.indexOf(']')).split('=');
                    switch(attrElements) {
                        case [name, value]: attrs.set(name, value);
                        case [name]: attrs.set(name, "true");
                        default: throw 'Invalid attributes: $attrElements';
                    }
                }
                default: throw 'Invalid attributes: $signatureRemaining';
            }

            signatureRemaining = signatureRemaining.substr(nextElementIndex+1);
            nextElementIndex = getNext(signatureRemaining.substr(1));
        }

        for (attrName in Reflect.fields(attrStruct)) {
            var value = Reflect.field(attrStruct, attrName);
            if (attrName == classAttrName) {
                classes = classes.concat(cast switch(Type.typeof(value)) {
                    case TObject: [for (key in Reflect.fields(value)) if (Reflect.field(value, key)) key];
                    case TClass(s): [value];  // Here we just assume that it is a string value.
                    default: throw "InvalidType passed to element.class";
                });
            } else if (tagName == 'input' && attrName == 'checked') {
                attrs.set(attrName, if (cast value) 'checked' else null);
            } else {
                attrs.set(attrName, value);
            }
        }

        if (classes.length > 0) {
            attrs.set('class', classes.join(" "));
        }

        if (paramChildArray != null) {
            for (child in paramChildArray) {
                if (Type.getClass(child) == String) {
                    // Add a string as a TextNode
                    childArray.push({
                        id:nodeCounter++,
                        tag:VirtualElementTools.TEXT_TAG,
                        children: [],
                        textValue: child
                    });
                } else {
                    childArray.push(child);
                }
            }
        }

        return {
            id:nodeCounter++,
            tag:tagName,
            isVoid:tagName.isVoidTag(),
            attrs:attrs,
            children:childArray
        };
    }

    /*
     * update will bring the `current` to parity with `next` and append all the necessary changes to `pendingChanges`.
     * Finally, it will return the new `current`
    */
    @:allow(starlight.lens.tests)
    function update(nextState:Array<VirtualElement>, currentState:Array<VirtualElement>, ?parentId:Int):Array<ElementUpdate> {
        // TODO: implement a keying algorithm for efficient reordering
        var updates:Array<ElementUpdate> = [];
        var currentStateItems = currentState.length;
        var nextStateItems = nextState.length;

        inline function place(func:ElementUpdate->Void, upd:ElementUpdate) {
#if pluginSupport
            updates.push(upd);
#else
            func(upd);
#end
        }

        for (index in 0...(if (currentStateItems > nextStateItems) currentStateItems else nextStateItems)) {
            var next = if (index < nextStateItems) nextState[index] else null;
            var current = if (index < currentStateItems) currentState[index] else null;
            var changingSelectValue = false;

            if (current == null) {
                // If there is nothing to compare, just create it.
                place(addElement, {
                    action:AddElement,
                    elementId:next.id,
                    tag:next.tag,
                    attrs:next.attrs,
                    textValue:next.textValue,
                    newParent:parentId,
                    newIndex:index
                });

                changingSelectValue = next.tag == 'select' && next.attrs.exists('value');

            } else if (next == null) {
                // If there is nothing there, just remove it.
                place(removeElement, {
                    action:RemoveElement,
                    elementId:current.id
                });
                continue;
            } else if (next.tag != current.tag || next.textValue != current.textValue) {
                // Remove the old element
                place(removeElement, {
                    action:RemoveElement,
                    elementId:current.id
                });
                // Update the new element
                place(addElement, {
                    action:AddElement,
                    elementId:next.id,
                    tag:next.tag,
                    attrs:next.attrs,
                    textValue:next.textValue,
                    newParent:parentId,
                    newIndex:index
                });

                changingSelectValue = next.tag == 'select' && next.attrs.exists('value');

            } else if (next.tag != VirtualElementTools.TEXT_TAG) {
                var attrDiff = new VirtualElementAttributes();
                var attrsAreEqual = true;

                for (key in current.attrs.keys()) {
                    var val;
                    if (next.attrs.exists(key)) {
                        val = next.attrs.get(key);
                        attrsAreEqual = attrsAreEqual && val == current.attrs.get(key);
                    } else {
                        val = null;
                        attrsAreEqual = false;
                    }
                    attrDiff.set(key, val);
                }

                for (key in next.attrs.keys()) {
                    if (!attrDiff.exists(key)) {
                        attrDiff.set(key, next.attrs.get(key));
                        attrsAreEqual = false;
                    }
                }

                if (!attrsAreEqual) {
                    // Update the current element
                    place(updateElement, {
                        action:UpdateElement,
                        elementId:current.id,
                        attrs:attrDiff
                    });
                }
                next.id = current.id;
            } else {
                next.id = current.id;
            }

#if pluginSupport
            updates = updates.concat(
                update(
                    if (next == null) [] else next.children,
                    if (current == null) [] else current.children,
                    next.id
                )
            );
#else
            update(
                if (next == null) [] else next.children,
                if (current == null) [] else current.children,
                next.id
            );
#end
            if (changingSelectValue) {
                var attrs = new VirtualElementAttributes();
                attrs.set('value', next.attrs.get('value'));
                place(updateElement, {
                    action:UpdateElement,
                    elementId:next.id,
                    attrs:attrs
                });
            }
        }

        return updates;
    }

    @:keep
    function view():Array<VirtualElement> {
        return [{
            id:nodeCounter++,
            tag:VirtualElementTools.TEXT_TAG,
            children: [],
            textValue:Type.getClassName(cast this) + ' does have have a view() method.'
        }];
    }

    public function render() {
        var nextState = view();
#if pluginSupport
        consumeUpdates(update(nextState, currentState));
#else
        update(nextState, currentState);
#end
        currentState = nextState;
    }

    public static function apply(vm:Lens, ?root:ElementType) {
        if (root != null) {
            vm.root = root;
        }
        vm.render();
    }

    function setAttributes(element:ElementType, attrs:VirtualElementAttributes, id:Int):Void {
        // TODO: Consider denormalizing element.tagName to avoid a DOM call.
        for (attrName in attrs.keys()) {
            var value = attrs.get(attrName);
            // TODO - potential speed optimization. elementPropertiesAttributes might do better broken out to separate conditions
            // FIXME - Normally we would use Reflect but it doesn't compile correctly such that firefox would work.
            if (untyped __js__("attrName in element") && elementPropertyAttributes.indexOf(attrName) == -1) {
                if (element.tagName != "input" || untyped __js__("element[attrName]") != value) {
                    var field = untyped __js__("element[attrName]");
                    if (untyped __js__("typeof field") == 'function' && attrName.substr(0, 2) != "on") {
                        postProcessing.set(attrName, id);
                    } else {
                        untyped __js__("element[attrName] = value");
                    }
                }
            } else {
                if (value == null) {
                    element.removeAttribute(attrName);
                } else {
                    element.setAttribute(attrName, value);
                }
            }
        }
    }

    function injectElement(element:ElementType, parent:ElementType, index:Int) {
#if js
        var nextSibling = parent.childNodes[index];
        if (nextSibling != null) {
            parent.insertBefore(element, nextSibling);
        } else {
            parent.appendChild(element);
        }
#end
    }

    inline function addElement(update:ElementUpdate) {
#if js
        var element:ElementType;
        var parent:ElementType;

        if (update.tag == '#text') {
            element = cast js.Browser.document.createTextNode(update.textValue);
        } else {
            element = cast js.Browser.document.createElement(update.tag);
            setAttributes(cast element, update.attrs, update.elementId);
        }
        elementCache.set(update.elementId, cast element);

        if (update.newParent == null) {
            parent = root;
        } else {
            parent = elementCache.get(update.newParent);
        }
        injectElement(element, parent, update.newIndex);
#end
    }

    inline function updateElement(update:ElementUpdate) {
#if js
        setAttributes(cast elementCache.get(update.elementId), update.attrs, update.elementId);
#end
    }

    inline function removeElement(update:ElementUpdate) {
#if js
        var element = elementCache.get(update.elementId);
        element.parentNode.removeChild(element);
        elementCache.remove(update.elementId);
#end
    }

    inline function moveElement(update:ElementUpdate) {
#if js
        injectElement(
            elementCache.get(update.elementId),
            elementCache.get(update.newParent),
            update.newIndex);
#end
    }

    @:allow(starlight.lens.tests)
    function consumeUpdates(updates:Array<ElementUpdate>) {
#if debugRendering
            trace('Starting update set.');
#end
        while (updates.length > 0) {
            var elementUpdate = updates.shift();
#if debugRendering
            trace(elementUpdate);
#end
            switch(elementUpdate.action) {
                case AddElement: addElement(elementUpdate);
                case UpdateElement: updateElement(elementUpdate);
                case RemoveElement: removeElement(elementUpdate);
                case MoveElement: moveElement(elementUpdate);
            }
        }

        for (method in postProcessing.keys()) {
            var id = postProcessing.get(method);
#if debugRendering
            trace('postProcess calling $method on $id');
#end
            var el = elementCache.get(id);
            Reflect.callMethod(el, Reflect.field(el, method), []);
            postProcessing.remove(method);
        }

#if debugRendering
            trace('Finished update set.');
#end
    }
}

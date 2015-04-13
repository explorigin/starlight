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
    ?oldParent:Int,
    ?oldIndex:Int,
    ?newParent:Int,
    ?newIndex:Int
}

#if js
    typedef ElementType = js.html.Element;
#else
    typedef ElementType = Dynamic;
#end


class Lens {
    static var parser = ~/((^|#|\.)([^#\.\[]+))|(\[.+\])/g;
    static var attrParser = ~/\[([A-z]+)(=([A-z]+))?\]/;      //  Not the most efficient but EReg has some pretty severe restrictions.
    static var elementPropertyAttributes = ~/^(list|style|form|type|width|height)$/i;

    static var nodeCounter = 0;

    var e = element;  //  A shortcut for easy access in the `view` method.
    var root:ElementType;
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
                attrStruct = {};
                paramChildArray = new Array<Dynamic>();
            }
            default: {
#if js
                throw 'Invalid Type passed to Lens.element for tag attributes';
#else
                throw 'Invalid Type passed to Lens.element for tag attributes: $attrStruct';
#end
            }
        }

        var classAttrName = Reflect.hasField(attrStruct, "class") ? "class" : "className";
        var keepGoing = parser.match(signature);

        while(keepGoing) {
            switch(parser.matched(2)) {
                case "": tagName = parser.matched(3);
                case "#": attrs.set("id", parser.matched(3));
                case ".": classes.push(parser.matched(3));
                default: {
                    if (parser.matched(4).charAt(0) == "[") {
                        if(attrParser.match(parser.matched(4))) {
                            if (attrParser.matched(3) != "") {
                                attrs.set(attrParser.matched(1), attrParser.matched(3));
                            } else if (attrParser.matched(2) != "") {
                                attrs.set(attrParser.matched(1), "");
                            } else {
                                attrs.set(attrParser.matched(1), "true");
                            }
                        }
                    }
                }
            }

            keepGoing = parser.match(parser.matchedRight());
        }

        if (classes.length > 0) {
            attrs.set('class', classes.join(" "));
        }

        for (attrName in Reflect.fields(attrStruct)) {
            var value = Reflect.field(attrStruct, attrName);
            if (attrName == classAttrName) {
                if (value != "") {
                    var cellValue = attrs.get(attrName);
                    attrs.set(attrName, (if (cellValue != null) cellValue else "") + " " + value);
                }
            } else {
                attrs.set(attrName, value);
            }
        }
        if (attrs.get('class') != null) {
#if js
            attrs.set('class', untyped __js__("attrs.get('class').trim()"));
#else
            attrs.set('class', attrs.get('class').trim());
#end
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
    public static function update(nextState:Array<VirtualElement>, currentState:Array<VirtualElement>, ?parentId:Int, ?parentIndex:Int):Array<ElementUpdate> {
        // TODO: implement a keying algorithm for efficient reordering
        var updates:Array<ElementUpdate> = [];

        for (index in 0...cast Math.max(nextState.length, currentState.length)) {
            var next = nextState[index];
            var current = currentState[index];
            var useNext = true;

            if (current == null) {
                // If there is nothing to compare, just create it.
                updates.push({
                    action:AddElement,
                    elementId:next.id,
                    tag:next.tag,
                    attrs:next.attrs,
                    textValue:next.textValue,
                    newParent:parentId,
                    newIndex:parentIndex
                });
            } else if (next == null) {
                // If there is nothing there, just remove it.
                updates.push({
                    action:RemoveElement,
                    elementId:current.id
                });
                continue;
            } else if (next.tag != current.tag || next.textValue != current.textValue) {
                // Remove the old element
                updates.push({
                    action:RemoveElement,
                    elementId:current.id
                });
                // Update the new element
                updates.push({
                    action:AddElement,
                    elementId:next.id,
                    tag:next.tag,
                    attrs:next.attrs,
                    textValue:next.textValue,
                    newParent:parentId,
                    newIndex:parentIndex
                });
            } else if (!next.attrs.attrEquals(current.attrs)) {
                // Update the current element
                var attrDiff = next.attrs;
                for (key in current.attrs.keys()) {
                    if (attrDiff.exists(key)) {
                        continue;
                    }
                    attrDiff.set(key, null);
                }

                updates.push({
                    action:UpdateElement,
                    elementId:next.id,
                    attrs:attrDiff
                });
            } else {
                useNext = false;
            }

            updates = updates.concat(
                update(
                    if (next == null) [] else next.children,
                    if (current == null) [] else current.children,
                    if (useNext) next.id else current.id,
                    index
                )
            );
        }

        return updates;
    }

    public function view():Array<VirtualElement> {
        return [{
            id:nodeCounter++,
            tag:VirtualElementTools.TEXT_TAG,
            children: [],
            textValue:Type.getClassName(cast this) + ' does have have a view() method.'
        }];
    }

    public function processUpdates() {
        var nextState = view();
        consumeUpdates(update(nextState, currentState));
        currentState = nextState;
    }

    public static function apply(vm:Lens, ?root:ElementType) {
        if (root != null) {
            vm.root = root;
        }
        vm.processUpdates();
    }

    public static function setAttributes(element:ElementType, attrs:VirtualElementAttributes):Void {
        // TODO: Consider denormalizing element.tagName to avoid a DOM call.
        for (attrName in attrs.keys()) {
            var value = attrs.get(attrName);
            // TODO - potential speed optimization. elementPropertiesAttributes might do better broken out to separate conditions
            if (Reflect.hasField(element, attrName) && !elementPropertyAttributes.match(attrName)) {
                if (element.tagName != "input" || Reflect.field(element, attrName) != value) {
                    Reflect.setField(element, attrName, value);
                }
            } else {
                element.setAttribute(attrName, value);
            }
        }
    }

    function insertElement(element:ElementType, parent:ElementType, index:Int) {
#if js
        var nextSibling = parent.childNodes[index];
        if (nextSibling != null) {
            parent.insertBefore(element, nextSibling);
        } else {
            parent.appendChild(element);
        }
#end
    }

    public function consumeUpdates(updates:Array<ElementUpdate>) {
        while (updates.length > 0) {
            var elementUpdate = updates.shift();
#if js
            switch(elementUpdate.action) {
                case AddElement: {
                    var element:ElementType;
                    var parent:ElementType;

                    if (elementUpdate.tag == '#text') {
                        element = cast js.Browser.document.createTextNode(elementUpdate.textValue);
                    } else {
                        element = cast js.Browser.document.createElement(elementUpdate.tag);
                        setAttributes(cast element, elementUpdate.attrs);
                    }
                    elementCache.set(elementUpdate.elementId, cast element);


                    if (elementCache.exists(elementUpdate.newParent)) {
                        parent = elementCache.get(elementUpdate.newParent);
                    } else {
                        parent = root;
                    }
                    insertElement(element, parent, elementUpdate.newIndex);
                }
                case UpdateElement: {
                    if (elementCache.exists(elementUpdate.elementId)) {
                        var element = elementCache.get(elementUpdate.elementId);
                        setAttributes(cast element, elementUpdate.attrs);
#if !js
                    } else {
                        trace('Tried to update a non-existant element: $elementUpdate');
#end
                    }
                }
                case RemoveElement: {
                    if (elementCache.exists(elementUpdate.elementId)) {
                        var element = elementCache.get(elementUpdate.elementId);
                        element.parentNode.removeChild(element);
                        elementCache.remove(elementUpdate.elementId);
                    }
                }
                case MoveElement: {
                    var parent = elementCache.get(elementUpdate.newParent);
                    var element = elementCache.get(elementUpdate.elementId);
                    if (parent != null && element != null) {
                        insertElement(element, parent, elementUpdate.newIndex);
#if !js
                    } else {
                        trace('Tried to move a non-existant element or to a non-existant element: $elementUpdate');
#end
                    }
                }
                default: trace('unsupported action');
            }
#end
        }
    }
}

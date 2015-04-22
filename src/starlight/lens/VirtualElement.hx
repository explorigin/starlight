package starlight.lens;

import haxe.ds.StringMap;

typedef VirtualElementAttributes = StringMap<Dynamic>;
typedef VirtualElementChildren = Array<VirtualElement>;
typedef VirtualElement = {
    id:Int,
    tag:String,
    children:VirtualElementChildren,
    ?isVoid:Bool,
    ?attrs:VirtualElementAttributes,
    ?textValue:String
}

class VirtualElementTools {
    static var BOOLEAN_ATTRIBUTES = [
        'autofocus',
        'checked',
        'disabled',
        'formnovalidate',
        'multiple',
        'readonly'
    ];
    public static var TEXT_TAG = '#text';
    static var VOID_TAGNAMES = ~/^(AREA|BASE|BR|COL|COMMAND|EMBED|HR|IMG|INPUT|KEYGEN|LINK|META|PARAM|SOURCE|TRACK|WBR)$/i;

    static inline public function isVoidTag(tag:String):Bool {
        return VOID_TAGNAMES.match(tag);
    }

    static inline public function isTextTag(tag:String):Bool {
        return tag == TEXT_TAG;
    }

    static public function toHTML(e:VirtualElement):String {
        if (e.isVoid) {
            var attrArray = [for (key in e.attrs.keys()) if (BOOLEAN_ATTRIBUTES.indexOf(key) == -1) '$key="${e.attrs.get(key)}"' else key];
            var attrString = ' ' + attrArray.join(' ');
            if (attrArray.length == 0) {
                attrString = '';
            }
            return '<${e.tag}$attrString>';
        } else if (e.tag == TEXT_TAG) {
            return e.textValue;
        } else {
            var attrArray = [for (key in e.attrs.keys()) '$key="${e.attrs.get(key)}"'];
            var attrString = ' ' + attrArray.join(' ');
            if (attrArray.length == 0) {
                attrString = '';
            }
            var childrenString:String = [for (child in e.children) VirtualElementTools.toHTML(child)].join('');
            return '<${e.tag}$attrString>$childrenString</${e.tag}>';
        }
        return '';
    }

    static public function childrenEquals(a:VirtualElementChildren, b:VirtualElementChildren):Bool {
        if (a.length == b.length) {
            var len = a.length;
            while(len-- != 0) {
                if (a[len] != b[len]) {
                    return false;
                }
            }
            return true;
        }
        return false;
    }
}

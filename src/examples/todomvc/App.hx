package todomvc;

import starlight.view.View in SLView;
import starlight.router.HistoryManager;
import js.html.InputElement;
import js.html.DOMElement;

using StringTools;

class View extends SLView {
    static inline var ENTER_KEY = 13;
    static inline var ESCAPE_KEY = 27;

    public var filter:String = 'all';
    var editingIndex:Int = -1;
    var todos:Array<Todo> = new Array<Todo>();
    var store:Store<Todo>;

    public function new(store:Store<Todo>) {
        super();

        this.store = store;
        todos = this.store.findAll();
    }

    function getFilteredTodos() {
        return todos.filter(function(todo) {
            return switch (filter) {
                case 'all': true;
                case 'completed': todo.completed;
                case 'active': !todo.completed;
                default: true;
            }
        });
    }

    function getActiveTodos() {
        return todos.filter(function(todo) {
            return !todo.completed;
        });
    }

    function findParent(el:DOMElement, parentTagName:String) {
        el = el.parentElement;
        parentTagName = parentTagName.toUpperCase();

        while (true) {
            if (el.tagName == parentTagName) {
                return el;
            }

            el = el.parentElement;

            if (el == js.Browser.document.body) {
                throw "No element by that tag.";
            }
        }
    }

    function indexFromEl(el:DOMElement) {
        var id:Int = Std.parseInt(findParent(el, 'li').dataset.id);
        var i = todos.length;

        while (i-- != 0) {
            if (todos[i].id == id) {
                return i;
            }
        }
        return -1;
    }

    function onNewTodoKeyUp(evt:js.html.KeyboardEvent) {
        var el:InputElement = cast evt.target;
        var val:String = el.value;

        if (evt.which != ENTER_KEY || val == "") {
            return;
        }

        var todo = new Todo(val);

        if(store.add(todo)) {
            todos.push(todo);
        }

        el.value = '';
        render();
    }

    function onToggleAllChange(evt:Dynamic) {
        var el:InputElement = cast evt.target;

        var isChecked = el.checked;

        store.overwrite(
            todos.map(function (todo:Todo):Todo {
                todo.completed = isChecked;
                return todo;
            })
        );

        render();
    }

    function onClearClick(evt:Dynamic) {
        if (store.overwrite(getActiveTodos())) {
            todos = store.findAll();
        }
        filter = 'all';
        render();
    }

    function onToggleChange(evt:Dynamic) {
        var el:InputElement = cast evt.target;
        var i = indexFromEl(el);
        todos[i].completed = el.checked;
        store.update(todos[i]);
        render();
    }

    function onLabelClick(evt:Dynamic) {
        var el:InputElement = cast evt.target;
        editingIndex = indexFromEl(el);
        render();
    }

    function onEditKeyUp(evt:Dynamic) {
        if (evt.which == ENTER_KEY) {
            evt.target.blur();
        }

        if (evt.which == ESCAPE_KEY) {
            evt.target.dataset.abort = 'true';
            evt.target.blur();
        }
    }

    function onEditBlur(evt:Dynamic) {
        var el:InputElement = cast evt.target;
        var i = indexFromEl(el);
        var val = el.value.trim();

        editingIndex = -1;

        if (evt.target.dataset.abort == 'true') {
            evt.target.dataset.abort = 'false';
            el.value = todos[i].title;
            render();
            return;
        }

        if (val != '') {
            todos[i].title = val;
            store.update(todos[i]);
        } else {
            if (store.remove(todos[i].id)) {
                todos.splice(i, 1);
            }
        }

        render();
    }

    function onDestroyClick(evt:Dynamic) {
        var el:js.html.DOMElement = cast evt.target;
        var i = indexFromEl(el);
        if (store.remove(todos[i].id)) {
            todos.splice(i, 1);
        }
        render();
    }

    override function view() {
        var currentTodos = getFilteredTodos();
        var todoCount = todos.length;
        var activeTodoCount = getActiveTodos().length;
        var completedTodos = todoCount - activeTodoCount;

        function itemView(index:Int, item:Todo) {
            return e('li', {
                    "data-id":item.id,
                    "class":{completed: item.completed, editing: index == editingIndex}
                }, [
                    e('div.view', [
                        e('input.toggle', {
                            type:"checkbox",
                            checked: item.completed,
                            onchange: onToggleChange
                        }),
                        e('label', {onclick: onLabelClick}, item.title),
                        e('button.destroy', {onclick: onDestroyClick})
                    ]),
                    if (index == editingIndex)
                        e('input.edit', {
                            value: item.title,
                            onkeyup: onEditKeyUp,
                            onblur: onEditBlur,
                            focus: true,
                            select: true
                        })
                    else
                        ''
                ]);
        }

        // var view =
        //     @section('#todoapp')
        //         @header('#header')
        //             @h1()
        //                 'todos'
        //             @input('#new-todo', placeholder="What needs to be done?", autofocus=true)
        //         @section('#main', class=if (todoCount == 0) "hidden" else "")
        //             @input('#toggle-all', type="checkbox")
        //             @label(for="toggle-all")
        //                 "Mark all as complete"
        //             @ul('#todo-list')
        //                 [for (item in todos) itemView(item)]
        //         @footer('#footer', class=if (todoCount == 0) "hidden" else "")
        //             @span('#todo-count')
        //                 @strong
        //                     activeTodoCount
        //                 if (activeTodoCount != 1) ' items left' else ' item left'
        //             @ul('#filters')
        //                 @li
        //                     @a(href="#/all", class=if (filter == 'all') "selected" else "")
        //                     "All"
        //                 @li
        //                     @a(href="#/active", class=if (filter == 'active') "selected" else "")
        //                     "Active"
        //                 @li
        //                     @a(href="#/completed", class=if (filter == 'completed') "selected" else "")
        //                     "Completed"
        //             @button('#clear-completed', class=if (completedTodos == 0) "hidden" else "")
        //                 'Clear completed (' + completedTodos + ')')
        //     @footer('#info')
        //         @p
        //             'Double-click to edit a todo'
        //         @p
        //             'Created by '
        //             @a(href="http://sindresorhus.com")
        //                 "Sindre Sorhus"
        //         @p
        //             'Ported to Starlight by '
        //             @a(href="http://github.com/explorigin")
        //                 "Timothy Farrell"

        return [
            e('section#todoapp', [
                e('header#header', [
                    e('h1', 'todos'),
                    e('input#new-todo', {
                        placeholder:"What needs to be done?",
                        autofocus:true,
                        onkeyup:onNewTodoKeyUp
                    })
                ]),
                e('section#main', {"class":{hidden: todoCount == 0}}, [
                    e('input#toggle-all', {"type":"checkbox", onchange:onToggleAllChange}),
                    e('label', {"for":"toggle-all"}, "Mark all as complete"),
                    e('ul#todo-list', [for (i in 0...currentTodos.length) itemView(i, currentTodos[i])])
                ]),
                e('footer#footer', {"class":if (todoCount == 0) "hidden" else ""}, [
                    e('span#todo-count', [
                        e('strong', activeTodoCount),
                        if (activeTodoCount != 1) ' items left' else ' item left'
                    ]),
                    e('ul#filters', [
                        e('li', [
                            e('a', {href:"#/all", "class":{selected: filter == 'all'}}, "All")
                        ]),
                        e('li', [
                            e('a', {href:"#/active", "class": {selected: filter == 'active'}}, "Active")
                        ]),
                        e('li', [
                            e('a', {href:"#/completed", "class":{selected: filter == 'completed'}}, "Completed")
                        ])
                    ]),
                    e('button#clear-completed',
                      {
                        "class":{hidden: completedTodos == 0},
                        onclick:onClearClick
                      },
                      'Clear completed (' + completedTodos + ')')
                ])
            ]),
            e('footer#info', [
                e('p', 'Double-click to edit a todo'),
                e('p', [
                    'Created by ',
                    e('a', {href:"http://sindresorhus.com"}, "Sindre Sorhus")
                ]),
                e('p', [
                    'Ported to Starlight by ',
                    e('a', {href:"http://github.com/explorigin"}, "Timothy Farrell")
                ])
            ])
        ];
    }
}

class App {
    static function main() {
        var store = new Store<Todo>('todomvc');
        var view = new View(store);

        var manager = new HistoryManager(function (newHash, oldHash) {
            view.filter = newHash;
            view.render();
        });
        manager.init('/all');
    }
}

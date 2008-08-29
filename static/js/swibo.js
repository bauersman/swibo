$(document).ready(do_stuff);

var listener;
var check_id = null;
var state = 0;
var cached_text = "";
var cached_index = 0;
var objectlist = {};
var obj_index = 0;
var moving = false;
var next_update = false;

function do_stuff() {
  setup_listener();
  setInterval(send_pending, 500);
}

function send_pending() {
  if(next_update) {
    send_data(next_update);
    next_update = false;
  }
}

function setup_listener() {
  if(check_id) {
    $("div#footer").text("check_state: clear");
    state = 0;
    clearInterval(check_id);
  }

  cached_text = "";
  cached_index = 0;

  listener = $.ajax({
    type: "GET",
    url: "/listen",
    cache: false,
    dataType: "text",
    success: function() {
      setup_listener();
    },
    error: function() {
      clearInterval(check_id);
      $("div#footer").text("check_state: Server went away");
    }
  });

  check_id = setInterval(check_listener, 100);
}

function send_data(data) {
  $.ajax({
    type: "GET",
    url: "/send?t="+JSON.stringify(data)
  });
}

function new_chatbox() {
  data = {type: "chatbox", top: 10, left: 10};
  //create_object(data);
  send_data({action: "create", data: {type: "chatbox", top: 10, left: 10}});
}

function chatbox_send(ev, obj) {
  ev.preventDefault();
  id = $(obj).parent().parent()[0].id;
  input = $(obj).children("input[name=t]");
  send_data({action: "update", id: id, data: {text: input.val()}});
  input.val("");
}

function check_listener() {
  state += 1;
  cached_text = listener.responseText;
  if(cached_text.length > cached_index) {
    chunk = cached_text.substr(cached_index);
    cached_index = cached_text.length;

    obj = JSON.parse(unescape(chunk));

    if(obj.action == "update") {
      if(obj.data.text) {
        $("#"+obj.id+" pre").append(obj.data.text+"\n");
      }
      if(!moving && (obj.data.top)) {
        o = $("#"+obj.id);
        o[0].style.top = obj.data.top;
        o[0].style.left = obj.data.left;
      }
    } else if(obj.action == "create") {
      o = create_object(obj.data);
      o.bind("mousemove", function(e){
        if(moving) {
          //$(this).find("pre").text("pos: top: "+this.style.top+" left: "+this.style.left);
          id = this.id;
          next_update = {action: "update", id: id, data: {top: this.style.top, left: this.style.left}};
        }
      });

      o.bind("mousedown", function(e){moving=true});
      o.bind("mouseup", function(e){moving=false});
    }
  }
  $("div#footer").text("check_state: "+state);
}

function create_object(obj) {
  o = $("#store ."+obj.type).clone();
  o[0].style.left = obj.left;
  o[0].style.top = obj.top;
  obj_index += 1;
  o[0].id = "obj_"+obj_index;
  
  $("#canvas").append(o);
  o.draggable();
  return o;
}

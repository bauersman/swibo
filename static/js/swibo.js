$(document).ready(do_stuff);

var listener;
var check_id = null;
var state = 0;
var cached_text = "";
var cached_index = 0;

function do_stuff() {
  setup_listener();
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

function send_data(event) {
  event.preventDefault();
  $.ajax({
    type: "GET",
    url: "/send?t="+$("#t").val()
  });
  $("#t").val("");
}

function check_listener() {
  state += 1;
  cached_text = listener.responseText;
  if(cached_text.length > cached_index) {
    chunk = cached_text.substr(cached_index);
    cached_index = cached_text.length;

    $("pre").append(unescape(chunk));
  }
  $("div#footer").text("check_state: "+state);
}

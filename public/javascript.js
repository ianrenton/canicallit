$("form").submit(function() {
  alert("hi");
  $(this).addClass("loading");
  return true;
});

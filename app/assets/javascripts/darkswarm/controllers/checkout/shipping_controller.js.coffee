Darkswarm.controller "ShippingCtrl", ($scope, $timeout, ShippingMethods, CurrentHub) ->
  angular.extend(this, new FieldsetMixin($scope))
  $scope.ShippingMethods = ShippingMethods
  $scope.CurrentHub = CurrentHub
  $scope.hub_email = CurrentHub.hub.email_address.split("").reverse().join("")
  $scope.now = Date.now()
  $scope.name = "shipping"
  $scope.nextPanel = "payment"

  $scope.summary = ->
    [$scope.Checkout.shippingMethod()?.name]
  
  $timeout $scope.onTimeout 

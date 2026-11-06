from django.urls import path

from . import views

app_name = "orders"

urlpatterns = [
    path("", views.OrderListView.as_view(), name="list"),
    path("create/", views.OrderCreateView.as_view(), name="create"),
    path("check-coupon/", views.CouponCheckView.as_view(), name="check-coupon"),
    path("offers/", views.OffersView.as_view(), name="offers"),
    path("<int:pk>/", views.OrderDetailView.as_view(), name="detail"),
    path("<int:pk>/accept/", views.MerchantOrderActionView.as_view(action="accept"), name="accept"),
    path("<int:pk>/ready/", views.MerchantOrderActionView.as_view(action="ready"), name="ready"),
    path("<int:pk>/complete/", views.MerchantOrderActionView.as_view(action="complete"), name="complete"),
    path("<int:pk>/reject/", views.MerchantOrderActionView.as_view(action="reject"), name="reject"),
    path("<int:pk>/cancel/", views.OrderCancelView.as_view(), name="cancel"),
    path("<int:pk>/assign/", views.AssignDeliveryView.as_view(), name="assign"),
    path("<int:pk>/location/", views.RiderLocationView.as_view(), name="location"),
]

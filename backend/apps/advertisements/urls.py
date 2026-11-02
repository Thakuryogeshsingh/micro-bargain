from django.urls import path

from . import views

app_name = "advertisements"

urlpatterns = [
    path("", views.MerchantAdListView.as_view(), name="list"),
    path("create/", views.AdCreateView.as_view(), name="create"),
    path("banners/", views.BannerListView.as_view(), name="banners"),
    path("<int:pk>/click/", views.AdClickView.as_view(), name="click"),
]
